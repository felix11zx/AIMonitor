import AppKit
import AIMonitorCore

if CommandLine.arguments.contains("--record-hook") {
    // Observer callbacks fail open and never add model-visible text or decisions.
    try? HookRecorder.record(FileHandle.standardInput.readDataToEndOfFile())
    exit(0)
}

if let index=CommandLine.arguments.firstIndex(of:"--diagnose-cli"),CommandLine.arguments.count > index+2 {
    let home=URL(fileURLWithPath:CommandLine.arguments[index+1])
    let events=URL(fileURLWithPath:CommandLine.arguments[index+2])
    do {
        var states=HookRecorder.readStates(directory:events)
        var result:[String:String]=[:]
        for agent in try Catalog.read(home:home) {
            guard var state=states[agent.id] else { result[agent.id]=AgentStatus.unknown.rawValue;continue }
            state.resolveCompletedTools(SessionTail.completedToolIDs(from:SessionTail.read(path:agent.rolloutPath) ?? Data()))
            if let pid=state.processID { state.reconcileProcess(isAlive:kill(pid,0) == 0 || errno == EPERM) }
            states[agent.id]=state;result[agent.id]=state.status.rawValue
        }
        print(String(data:try JSONEncoder().encode(result),encoding:.utf8)!);exit(0)
    } catch { fputs("CLI-Status konnte nicht gelesen werden.\n",stderr);exit(1) }
}

if CommandLine.arguments.contains("--diagnose") {
    Task {
        let rpc=CodexRPC()
        let home=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
        do {
            let snapshot=try await rpc.readLimits(executable:MonitorStore.findCodex(),home:home)
            for window in snapshot.windows { print("\(window.id) remaining=\(window.remainingPercent.map(String.init(describing:)) ?? "unknown") reset=\(window.resetAt?.timeIntervalSince1970.description ?? "unknown")") }
            print("catalog=\(try Catalog.read(home:home).count)")
            await rpc.shutdown();exit(0)
        } catch { print(error.localizedDescription);await rpc.shutdown();exit(1) }
    }
    RunLoop.main.run()
}

MainActor.assumeIsolated {
    let app=NSApplication.shared
    let delegate=AppDelegate()
    app.delegate=delegate
    withExtendedLifetime(delegate) { app.run() }
}
