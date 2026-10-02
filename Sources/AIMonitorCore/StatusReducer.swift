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
    public init(sessionID: String, turnID: String?, kind: String, toolID: String?, toolName: String?, timestamp: Double, processID: Int32?) {
        self.sessionID=sessionID; self.turnID=turnID; self.kind=kind; self.toolID=toolID; self.toolName=toolName; self.timestamp=timestamp; self.processID=processID
    }
}

public struct CLIState {
    public private(set) var status: AgentStatus = .unknown
    public private(set) var turnID: String?
    public private(set) var timestamp: Double = 0
    public private(set) var processID: Int32?
    private var pending = Set<String>()
    public init() {}
    public mutating func apply(_ event: HookEvent) {
        guard event.timestamp >= timestamp else { return }
        if event.kind == "UserPromptSubmit" { pending.removeAll(); turnID=event.turnID; status = .working }
        else {
            guard event.turnID == nil || turnID == nil || event.turnID == turnID else { return }
            if turnID == nil { turnID = event.turnID }
            switch event.kind {
            case "Stop", "Interrupt", "SessionEnd": pending.removeAll(); status = .idle
            case "SessionStart": status = .idle
            case "PermissionRequest": pending.insert(event.toolID ?? event.toolName ?? "permission"); status = .needsInput
            case "PreToolUse":
                if Self.isInputTool(event.toolName) { pending.insert(event.toolID ?? event.toolName ?? "input"); status = .needsInput }
            case "PostToolUse":
                pending.remove(event.toolID ?? event.toolName ?? "permission")
                status = pending.isEmpty ? .working : .needsInput
            default: break
            }
        }
        timestamp = event.timestamp; processID = event.processID ?? processID
    }
    public mutating func reconcileProcess(isAlive: Bool) { if !isAlive { status = .idle; pending.removeAll() } }
    public static func isInputTool(_ name: String?) -> Bool {
        guard let name else { return false }; return name.contains("request_user_input") || name.contains("requestUserInput") || name.contains("elicitation")
    }
}
