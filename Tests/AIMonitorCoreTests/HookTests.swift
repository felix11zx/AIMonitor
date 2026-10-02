import XCTest
@testable import AIMonitorCore

final class HookTests: XCTestCase {
    func testInstallerPreservesOtherHooksAndRemovesOnlyItsEntries() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let original = #"{"description":"personal","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}"#
        try Data(original.utf8).write(to: home.appendingPathComponent("hooks.json"))
        try HookInstaller.setEnabled(true, home: home, executable: "/tmp/AIMonitor.app/Contents/MacOS/AIMonitor")
        try HookInstaller.setEnabled(true, home: home, executable: "/tmp/AIMonitor.app/Contents/MacOS/AIMonitor")
        let installed = try JSONValue.parse(String(contentsOf: home.appendingPathComponent("hooks.json"), encoding: .utf8))
        XCTAssertEqual(installed["hooks"]["Stop"].array?.count, 2)
        XCTAssertEqual(installed["description"].string, "personal")
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("hooks.json.aimonitor-backup"), encoding: .utf8), original)
        try HookInstaller.setEnabled(false, home: home, executable: "/tmp/AIMonitor.app/Contents/MacOS/AIMonitor")
        let removed = try JSONValue.parse(String(contentsOf: home.appendingPathComponent("hooks.json"), encoding: .utf8))
        XCTAssertEqual(removed["hooks"]["Stop"].array?.count, 1)
        XCTAssertEqual(removed["hooks"]["Stop"].array?.first?["hooks"].array?.first?["command"].string, "echo mine")
    }
    func testRecorderDiscardsPromptAndArgumentsAndPairsPermissionWithPostTool() throws {
        let permission = try HookRecorder.event(from: JSONValue.parse(#"{"session_id":"s","turn_id":"t","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"private command","description":"reason"},"prompt":"private prompt"}"#), timestamp: 1)
        let post = try HookRecorder.event(from: JSONValue.parse(#"{"session_id":"s","turn_id":"t","hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"call-id","tool_input":{"command":"private command"}}"#), timestamp: 2)
        XCTAssertEqual(permission.toolID, post.toolID)
        let text = String(data: try JSONEncoder().encode(permission), encoding: .utf8)!
        XCTAssertFalse(text.contains("private"))
        var state = CLIState(); state.apply(permission); XCTAssertEqual(state.status, .needsInput)
        state.apply(post); XCTAssertEqual(state.status, .working)
        state.reconcileProcess(isAlive: false); XCTAssertEqual(state.status, .idle)
    }
    func testInvalidHookConfigurationIsPreserved() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let original = #"{"hooks":{"Stop":{"personal":"unexpected"}}}"#
        let file=home.appendingPathComponent("hooks.json")
        try Data(original.utf8).write(to:file)
        XCTAssertThrowsError(try HookInstaller.setEnabled(true,home:home,executable:"/tmp/monitor"))
        XCTAssertEqual(try String(contentsOf:file,encoding:.utf8),original)
    }
    func testIdenticalConcurrentPermissionsRequireBothResults() {
        var state=CLIState()
        state.apply(HookEvent(sessionID:"s",turnID:"t",kind:"PermissionRequest",toolID:"same",toolName:"Bash",timestamp:1,processID:nil))
        state.apply(HookEvent(sessionID:"s",turnID:"t",kind:"PermissionRequest",toolID:"same",toolName:"Bash",timestamp:2,processID:nil))
        state.apply(HookEvent(sessionID:"s",turnID:"t",kind:"PostToolUse",toolID:"same",toolName:"Bash",timestamp:3,processID:nil))
        XCTAssertEqual(state.status,.needsInput)
        state.apply(HookEvent(sessionID:"s",turnID:"t",kind:"PostToolUse",toolID:"same",toolName:"Bash",timestamp:4,processID:nil))
        XCTAssertEqual(state.status,.working)
    }
    func testDeniedApprovalResolvesFromExactRolloutCallID() throws {
        var state=CLIState()
        state.apply(HookEvent(sessionID:"s",turnID:"t",kind:"UserPromptSubmit",toolID:nil,toolName:nil,timestamp:1,processID:1))
        state.apply(HookEvent(sessionID:"s",turnID:"t",kind:"PreToolUse",toolID:"Bash:hash",toolName:"Bash",timestamp:2,processID:1,requestID:"call1"))
        state.apply(HookEvent(sessionID:"s",turnID:"t",kind:"PermissionRequest",toolID:"Bash:hash",toolName:"Bash",timestamp:3,processID:1))
        XCTAssertEqual(state.status,.needsInput)
        state.resolveCompletedTools(["unrelated"]);XCTAssertEqual(state.status,.needsInput)
        let data=Data(#"{"type":"response_item","payload":{"type":"function_call_output","call_id":"call1","output":"Rejected by user"}}"#.utf8)+Data([10])
        state.resolveCompletedTools(SessionTail.completedToolIDs(from:data))
        XCTAssertEqual(state.status,.working)
    }
    func testSnapshotRetainsPendingStateAcrossRecorderInvocations() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        try HookRecorder.record(Data(#"{"session_id":"s","turn_id":"t","hook_event_name":"PreToolUse","tool_name":"request_user_input","tool_use_id":"call1","tool_input":{"questions":[]}}"#.utf8),directory:dir)
        XCTAssertEqual(HookRecorder.readStates(directory:dir)["s"]?.status,.needsInput)
        try HookRecorder.record(Data(#"{"session_id":"s","turn_id":"t","hook_event_name":"PostToolUse","tool_name":"request_user_input","tool_use_id":"call1","tool_input":{"questions":[]}}"#.utf8),directory:dir)
        XCTAssertEqual(HookRecorder.readStates(directory:dir)["s"]?.status,.working)
    }
    func testOversizedArrayPatchThrowsInsteadOfTrapping() throws {
        var json=JSONValue.array([.null])
        XCTAssertThrowsError(try json.patch(path:[.number(1e300)],operation:"remove",value:.null))
        XCTAssertThrowsError(try json.patch(path:[.number(0.5)],operation:"remove",value:.null))
    }
    func testAmbiguousIdenticalToolsDoNotClearAnotherApproval() {
        var state=CLIState()
        for (id,time) in [("a",1.0),("b",2.0)] { state.apply(HookEvent(sessionID:"s",turnID:"t",kind:"PreToolUse",toolID:"same",toolName:"Bash",timestamp:time,processID:nil,requestID:id)) }
        state.apply(HookEvent(sessionID:"s",turnID:"t",kind:"PermissionRequest",toolID:"same",toolName:"Bash",timestamp:3,processID:nil))
        XCTAssertEqual(state.status,.needsInput)
        state.resolveCompletedTools(["b"])
        XCTAssertEqual(state.status,.unknown) // ID-less permission cannot safely be assigned to a or b.
        state.resolveCompletedTools(["a"])
        XCTAssertEqual(state.status,.working)
    }
    func testResolvedRejectionCannotReappearInNewRecorderSnapshot() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        func record(_ text:String) throws { try HookRecorder.record(Data(text.utf8),directory:dir) }
        try record(#"{"session_id":"s","turn_id":"t","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"a","tool_input":{"command":"test"}}"#)
        try record(#"{"session_id":"s","turn_id":"t","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"test"}}"#)
        XCTAssertEqual(HookRecorder.readStates(directory:dir)["s"]?.status,.needsInput)
        _ = try HookRecorder.resolveTools(sessionID:"s",ids:["a"],directory:dir)
        try record(#"{"session_id":"s","turn_id":"t","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"b","tool_input":{"command":"other"}}"#)
        XCTAssertEqual(HookRecorder.readStates(directory:dir)["s"]?.status,.working)
    }
    func testRejectedResultOutsideTailIsStillFound() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let result = #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"a","output":"Rejected"}}"# + "\n"
        try Data((result+String(repeating:"{\"type\":\"event_msg\"}\n",count:15000)).utf8).write(to:file)
        XCTAssertFalse(SessionTail.completedToolIDs(from:SessionTail.read(path:file.path)!).contains("a"))
        XCTAssertTrue(SessionTail.completedToolIDs(path:file.path,matching:["a"]).contains("a"))
    }
    func testDelayedToolCompletionCannotReviveEndedTurn() {
        for ending in ["Stop","Interrupt","SessionEnd"] {
            var state=CLIState()
            state.apply(HookEvent(sessionID:"s",turnID:"t",kind:"UserPromptSubmit",toolID:nil,toolName:nil,timestamp:1,processID:1))
            state.apply(HookEvent(sessionID:"s",turnID:"t",kind:"PreToolUse",toolID:"same",toolName:"Bash",timestamp:2,processID:1,requestID:"a"))
            state.apply(HookEvent(sessionID:"s",turnID:"t",kind:ending,toolID:nil,toolName:nil,timestamp:3,processID:1))
            state.apply(HookEvent(sessionID:"s",turnID:"t",kind:"PostToolUse",toolID:"same",toolName:"Bash",timestamp:4,processID:1,requestID:"a"))
            XCTAssertEqual(state.status,.idle,ending)
            state.apply(HookEvent(sessionID:"s",turnID:"new",kind:"UserPromptSubmit",toolID:nil,toolName:nil,timestamp:5,processID:1))
            XCTAssertEqual(state.status,.working)
        }
    }
    func testSessionTailIgnoresPartialFinalLineAndReadsCompletion() throws {
        let data = Data("{\"type\":\"event_msg\",\"timestamp\":\"2026-10-02T20:00:00Z\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"t\"}}\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"t\"}}\n{\"type\":".utf8)
        XCTAssertEqual(SessionTail.status(from: data), .idle)
    }
}
