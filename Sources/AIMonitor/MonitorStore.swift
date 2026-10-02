import AppKit
import Combine
import AIMonitorCore

@MainActor final class MonitorStore: ObservableObject {
    @Published var agents: [AgentRecord]=[]
    @Published var statuses: [String:AgentStatus]=[:]
    @Published var windows: [UsageWindow]=[]
    @Published var lastRefresh: Date?
    @Published var limitError: String?
    @Published var desktopConnected=false
    @Published var desktopMessage="Verbindung wird hergestellt …"
    @Published var cliEnabled=false
    @Published var hookMessage: String?
    @Published var catalogError: String?
    @Published var isRefreshing=false
    @Published var appearance: String { didSet { UserDefaults.standard.set(appearance,forKey:"appearance");applyAppearance() } }
    @Published var interval: Double { didSet { UserDefaults.standard.set(interval,forKey:"refreshInterval");nextRefresh = .distantPast } }
    @Published private(set) var homePath: String
    @Published private(set) var executablePath: String
    private let rpc=CodexRPC()
    private var desktop=DesktopIPC()
    private var desktopStatuses:[String:AgentStatus]=[:]
    private var cliStates:[String:CLIState]=[:]
    private var loop:Task<Void,Never>?
    private var nextRefresh=Date.distantPast
    private var resetAttempts=Set<String>()
    private var generation=0
    var onStatusChanged: (() -> Void)?
    var home: URL { URL(fileURLWithPath:NSString(string:homePath).expandingTildeInPath,isDirectory:true) }
    var aggregate: AgentStatus { AgentStatus.aggregate(agents.map { statuses[$0.id] ?? .unknown }) }
    var visibleAgents: [AgentRecord] {
        let active=agents.filter { [.working,.needsInput].contains(statuses[$0.id] ?? .unknown) }
        let activeIDs=Set(active.map(\.id))
        return active + Array(agents.filter { !activeIDs.contains($0.id) }.prefix(6))
    }
    init() {
        let defaults=UserDefaults.standard
        appearance=defaults.string(forKey:"appearance") ?? "system"
        let stored=defaults.double(forKey:"refreshInterval");interval=[15,30,60].contains(stored) ? stored : 30
        homePath=defaults.string(forKey:"codexHome") ?? ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        executablePath=NSString(string:defaults.string(forKey:"codexExecutable") ?? Self.findCodex()).expandingTildeInPath
        cliEnabled=HookInstaller.isEnabled(home:home)
    }
    nonisolated static func findCodex() -> String {
        ["/opt/homebrew/bin/codex","/usr/local/bin/codex","/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex","/Applications/Codex.app/Contents/Resources/codex"].first { FileManager.default.isExecutableFile(atPath:$0) } ?? "/opt/homebrew/bin/codex"
    }
    func start() {
        guard loop == nil else { return }
        applyAppearance()
        let token=generation
        desktop.observe(home:home,ids:[]) { [weak self] event in
            Task { @MainActor in
                guard let self,self.generation == token else { return }
                switch event {
                case .connected: self.desktopConnected=true;self.desktopMessage="Desktop verbunden"
                case .status(let id,let status): self.desktopStatuses[id]=status;self.statuses[id]=status;self.onStatusChanged?()
                case .disconnected(let message):
                    self.desktopConnected=false;self.desktopMessage=message;self.desktopStatuses.removeAll()
                    for agent in self.agents where agent.source == "Desktop" { self.statuses[agent.id] = .unknown };self.onStatusChanged?()
                }
            }
        }
        loop=Task { [weak self] in
            while !Task.isCancelled {
                await self?.reconcile()
                guard let self else { return }
                if Date() >= self.nextRefresh { self.refresh() }
                for window in self.windows {
                    if let reset=window.resetAt,reset <= Date(),self.lastRefresh.map({ $0 < reset }) == true,!self.resetAttempts.contains(window.id+reset.description) {
                        self.resetAttempts.insert(window.id+reset.description);self.refresh()
                    }
                }
                try? await Task.sleep(nanoseconds:2_000_000_000)
            }
        }
        refresh()
    }
    func stop() { loop?.cancel();loop=nil;desktop.stop();Task { await rpc.shutdown() } }
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing=true;nextRefresh=Date().addingTimeInterval(interval)
        let executable=executablePath,home=home,token=generation
        Task {
            do {
                let snapshot=try await rpc.readLimits(executable:executable,home:home,onLimitsChanged:{ [weak self] in
                    Task { @MainActor in
                        guard let self,self.generation == token,!self.isRefreshing else { return }
                        self.nextRefresh = .distantPast
                    }
                })
                guard generation == token else { isRefreshing=false;return }
                windows=snapshot.windows;lastRefresh=Date();limitError=snapshot.windows.isEmpty ? "Für dieses Konto wurden keine Limits geliefert." : nil
            } catch { if generation == token { limitError=error.localizedDescription } }
            isRefreshing=false
        }
    }
    private func reconcile() async {
        let home=home,token=generation
        let data=await Task.detached(priority:.utility) { () -> ([AgentRecord],[String:CLIState],[String:AgentStatus],[String:Set<String>],String?) in
            do {
                let agents=try Catalog.read(home:home)
                let tails=Dictionary(uniqueKeysWithValues:agents.filter { $0.source == "CLI" }.map { ($0.id,SessionTail.read(path:$0.rolloutPath) ?? Data()) })
                let fallback=tails.mapValues { SessionTail.status(from:$0) == .idle ? AgentStatus.idle : .unknown }
                var states=HookRecorder.readStates()
                var completed=tails.mapValues { SessionTail.completedToolIDs(from:$0) }
                for agent in agents where agent.source == "CLI" {
                    guard let state=states[agent.id] else { continue }
                    let absent=state.pendingRequestIDs.subtracting(completed[agent.id] ?? [])
                    if !absent.isEmpty { completed[agent.id,default:[]].formUnion(SessionTail.completedToolIDs(path:agent.rolloutPath,matching:absent)) }
                    if let updated=try? HookRecorder.resolveTools(sessionID:agent.id,ids:completed[agent.id] ?? []) { states[agent.id]=updated }
                }
                return(agents,states,fallback,completed,nil)
            } catch { return([],[:],[:],[:],"Sessiondaten: "+error.localizedDescription) }
        }.value
        guard generation == token else { return }
        if let error=data.4 {
            catalogError=error
            for agent in agents where agent.source == "CLI" { statuses[agent.id] = .unknown }
            onStatusChanged?();return
        }
        catalogError=nil;agents=data.0
        cliEnabled=HookInstaller.isEnabled(home:home)
        for (id,state) in data.1 { if state.timestamp > (cliStates[id]?.timestamp ?? 0) { cliStates[id]=state } }
        for agent in agents {
            if agent.source == "Desktop" { statuses[agent.id]=desktopConnected ? desktopStatuses[agent.id] ?? .unknown : .unknown }
            else {
                if var state=cliStates[agent.id] {
                    state.resolveCompletedTools(data.3[agent.id] ?? [])
                    if let pid=state.processID { state.reconcileProcess(isAlive:kill(pid,0) == 0 || errno == EPERM) }
                    cliStates[agent.id]=state;statuses[agent.id]=state.status
                } else { statuses[agent.id]=data.2[agent.id] ?? .unknown }
            }
        }
        desktop.update(ids:agents.filter { $0.source == "Desktop" }.map(\.id))
        onStatusChanged?()
    }
    func configure(home: String, executable: String) {
        stop();generation+=1;desktop=DesktopIPC();desktopStatuses.removeAll();cliStates.removeAll();statuses.removeAll();windows=[];lastRefresh=nil
        desktopConnected=false;desktopMessage="Verbindung wird hergestellt …";catalogError=nil;hookMessage=nil;limitError=nil
        homePath=home;executablePath=NSString(string:executable).expandingTildeInPath
        UserDefaults.standard.set(home,forKey:"codexHome");UserDefaults.standard.set(executablePath,forKey:"codexExecutable")
        nextRefresh = .distantPast;resetAttempts.removeAll();start()
    }
    func setHooks(_ enabled: Bool) {
        guard let executable=Bundle.main.executableURL?.path else { return }
        let home=home,token=generation
        Task {
            do {
                try await Task.detached(priority:.utility) { try HookInstaller.setEnabled(enabled,home:home,executable:executable) }.value
                guard generation == token else { return }
                cliEnabled=enabled;hookMessage=enabled ? "Hooks installiert. CLI neu starten und unter /hooks bestätigen." : "AIMonitor-Hooks entfernt. Eigene Hooks bleiben erhalten."
            } catch { if generation == token { hookMessage=error.localizedDescription } }
        }
    }
    func applyAppearance() {
        NSApp.appearance=appearance == "dark" ? NSAppearance(named:.darkAqua) : appearance == "light" ? NSAppearance(named:.aqua) : nil
    }
}
