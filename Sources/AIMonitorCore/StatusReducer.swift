import Foundation

public struct DesktopState {
    public private(set) var json: JSONValue = .null
    public private(set) var revision: Double?
    public init() {}
    public var status: AgentStatus {
        let runtime = json["threadRuntimeStatus"]
        let type = runtime["type"].string
        if type == "idle" { return .idle }
        if type == "active" {
            if !(json["requests"].array ?? []).isEmpty || (runtime["activeFlags"].array ?? []).contains(where: { ["waitingOnApproval", "waitingOnUserInput"].contains($0.string ?? "") }) { return .needsInput }
            return .working
        }
        return .unknown
    }
    public mutating func apply(_ change: JSONValue) throws {
        do {
            guard let next = change["revision"].number else { throw MonitorError.invalid("IPC-Revision fehlt") }
            if change["type"].string == "snapshot" { json = change["conversationState"]; revision = next; return }
            guard change["type"].string == "patches", let revision, change["baseRevision"].number == revision, next > revision else { throw MonitorError.invalid("IPC-Snapshot muss erneut geladen werden") }
            var candidate = json
            for patch in change["patches"].array ?? [] {
                guard let path = patch["path"].array, let op = patch["op"].string, ["add","remove","replace"].contains(op) else { throw MonitorError.invalid("Unbekannter IPC-Patch") }
                try candidate.patch(path: path, operation: op, value: patch["value"])
            }
            json = candidate; self.revision = next
        } catch { json = .null; revision = nil; throw error }
    }
}

public struct HookEvent: Codable, Sendable {
    public let sessionID: String
    public let turnID: String?
    public let kind: String
    public let toolID: String?
    public let toolName: String?
    public let timestamp: Double
    public let processID: Int32?
    public let requestID: String?
    public init(sessionID: String, turnID: String?, kind: String, toolID: String?, toolName: String?, timestamp: Double, processID: Int32?, requestID: String? = nil) {
        self.sessionID=sessionID; self.turnID=turnID; self.kind=kind; self.toolID=toolID; self.toolName=toolName; self.timestamp=timestamp; self.processID=processID; self.requestID=requestID
    }
}

public struct CLIState: Codable, Sendable, Equatable {
    public private(set) var status: AgentStatus = .unknown
    public private(set) var turnID: String?
    public private(set) var timestamp: Double = 0
    public private(set) var processID: Int32?
    private var pending: [String:Int] = [:]
    private var calls: [String:[String]] = [:]
    private var ambiguousGroups = Set<String>()
    private var uncertainGroups = Set<String>()
    private var turnEnded=false
    public var pendingRequestIDs: Set<String> { Set(pending.keys.filter { !ambiguousGroups.contains($0) }).union(ambiguousGroups.flatMap { calls[$0] ?? [] }) }
    public init() {}
    public mutating func apply(_ event: HookEvent) {
        guard event.timestamp >= timestamp else { return }
        if turnEnded,["PreToolUse","PermissionRequest","PostToolUse"].contains(event.kind) { return }
        if !["UserPromptSubmit","SessionStart"].contains(event.kind), let current=processID,let incoming=event.processID,current != incoming { return }
        if event.kind == "UserPromptSubmit" { pending.removeAll(); calls.removeAll(); ambiguousGroups.removeAll();uncertainGroups.removeAll(); turnID=event.turnID;turnEnded=false; status = .working }
        else {
            guard event.turnID == nil || turnID == nil || event.turnID == turnID else { return }
            if turnID == nil { turnID = event.turnID }
            switch event.kind {
            case "Stop", "Interrupt", "SessionEnd": pending.removeAll(); calls.removeAll(); ambiguousGroups.removeAll();uncertainGroups.removeAll();turnEnded=true; status = .idle
            case "SessionStart": pending.removeAll();calls.removeAll();ambiguousGroups.removeAll();uncertainGroups.removeAll();turnID=nil;turnEnded=true;status = .idle
            case "PermissionRequest":
                let digest=event.toolID ?? event.toolName ?? "permission"
                let candidates=(calls[digest] ?? []).filter { pending[$0] == nil }
                let key=event.requestID ?? (candidates.count == 1 ? candidates[0] : digest)
                if event.requestID == nil, candidates.count > 1 { ambiguousGroups.insert(digest) }
                pending[key,default:0] += 1; status = .needsInput
            case "PreToolUse":
                if let digest=event.toolID, let id=event.requestID { calls[digest,default:[]].append(id) }
                if Self.isInputTool(event.toolName) { pending[event.requestID ?? event.toolID ?? event.toolName ?? "input",default:0] += 1; status = .needsInput }
            case "PostToolUse":
                let key=event.requestID.flatMap { pending[$0] != nil ? $0 : nil } ?? event.toolID ?? event.toolName ?? "permission"
                if let count=pending[key], !(ambiguousGroups.contains(key) && event.requestID != nil) { if count > 1 { pending[key]=count-1 } else { pending.removeValue(forKey:key) } }
                if let id=event.requestID { resolveCompletedTools([id]) }
                updatePendingStatus()
            default: break
            }
        }
        timestamp = event.timestamp; processID = event.processID ?? processID
    }
    public mutating func reconcileProcess(isAlive: Bool) { if !isAlive { status = .idle;turnEnded=true;pending.removeAll();calls.removeAll();ambiguousGroups.removeAll();uncertainGroups.removeAll() } }
    public mutating func resolveCompletedTools(_ ids: Set<String>) {
        // Rejected approvals do not emit PostToolUse; their exact call ID has a rollout result.
        guard !turnEnded else { return }
        var resolved=false
        for id in ids where pending[id] != nil { pending.removeValue(forKey:id); resolved=true }
        for key in Array(calls.keys) {
            let before=calls[key] ?? []
            calls[key]?.removeAll { ids.contains($0) }
            if ambiguousGroups.contains(key), before.contains(where:{ids.contains($0)}) {
                resolved=true
                if calls[key]?.isEmpty == true { pending.removeValue(forKey:key);ambiguousGroups.remove(key);uncertainGroups.remove(key) }
                else { uncertainGroups.insert(key) }
            }
            if calls[key]?.isEmpty == true { calls.removeValue(forKey:key) }
        }
        if resolved { updatePendingStatus() }
    }
    private mutating func updatePendingStatus() {
        if pending.isEmpty { status = .working }
        else if pending.keys.contains(where:{ !ambiguousGroups.contains($0) || !uncertainGroups.contains($0) }) { status = .needsInput }
        else { status = .unknown }
    }
    public static func isInputTool(_ name: String?) -> Bool {
        guard let name else { return false }; return name.contains("request_user_input") || name.contains("requestUserInput") || name.contains("elicitation")
    }
}
