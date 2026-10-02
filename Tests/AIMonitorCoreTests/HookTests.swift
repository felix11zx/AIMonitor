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
    func testSessionTailIgnoresPartialFinalLineAndReadsCompletion() throws {
        let data = Data("{\"type\":\"event_msg\",\"timestamp\":\"2026-10-02T20:00:00Z\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"t\"}}\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"t\"}}\n{\"type\":".utf8)
        XCTAssertEqual(SessionTail.status(from: data), .idle)
    }
}
