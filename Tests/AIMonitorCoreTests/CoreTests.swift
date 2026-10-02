import XCTest
@testable import AIMonitorCore

final class CoreTests: XCTestCase {
    func testBucketsOverrideLegacyAndMissingUsageStaysMissing() throws {
        let input = try JSONValue.parse(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1790960000},"secondary":{"windowDurationMins":10080}},"other":{"primary":{"usedPercent":130,"windowDurationMins":60}}}}"#)
        let snapshot = UsageSnapshot.decode(input)
        XCTAssertEqual(snapshot.windows.count, 3)
        XCTAssertEqual(snapshot.windows.first(where: { $0.id == "codex.primary" })?.remainingPercent, 75)
        XCTAssertEqual(snapshot.windows.first(where: { $0.id == "codex.secondary" })?.remainingPercent, nil)
        XCTAssertEqual(snapshot.windows.first(where: { $0.id == "other.primary" })?.remainingPercent, 0)
        XCTAssertEqual(snapshot.windows.first(where: { $0.id == "codex.primary" })?.resetAt?.timeIntervalSince1970, 1790960000)
    }

    func testDesktopRequestsKeepOrangeUntilAllAreResolvedAndRejectRevisionGap() throws {
        var state = DesktopState()
        try state.apply(JSONValue.parse(#"{"type":"snapshot","revision":2,"conversationState":{"threadRuntimeStatus":{"type":"active","activeFlags":[]},"requests":[{"id":"a"},{"id":"b"}]}}"#))
        XCTAssertEqual(state.status, .needsInput)
        try state.apply(JSONValue.parse(#"{"type":"patches","baseRevision":2,"revision":3,"patches":[{"op":"remove","path":["requests",0]}]}"#))
        XCTAssertEqual(state.status, .needsInput)
        try state.apply(JSONValue.parse(#"{"type":"patches","baseRevision":3,"revision":4,"patches":[{"op":"remove","path":["requests",0]}]}"#))
        XCTAssertEqual(state.status, .working)
        XCTAssertThrowsError(try state.apply(JSONValue.parse(#"{"type":"patches","baseRevision":6,"revision":7,"patches":[]}"#)))
        XCTAssertEqual(state.status, .unknown)
    }

    func testDesktopUnknownIsNotIdleAndWaitingFlagIsOrange() throws {
        var state = DesktopState()
        XCTAssertEqual(state.status, .unknown)
        try state.apply(JSONValue.parse(#"{"type":"snapshot","revision":1,"conversationState":{"threadRuntimeStatus":{"type":"active","activeFlags":["waitingOnUserInput"]},"requests":[]}}"#))
        XCTAssertEqual(state.status, .needsInput)
        try state.apply(JSONValue.parse(#"{"type":"snapshot","revision":2,"conversationState":{"threadRuntimeStatus":{"type":"idle"},"requests":[]}}"#))
        XCTAssertEqual(state.status, .idle)
    }

    func testCLIStaleTurnCannotClearNewTurn() {
        var state = CLIState()
        state.apply(HookEvent(sessionID: "s", turnID: "one", kind: "UserPromptSubmit", toolID: nil, toolName: nil, timestamp: 1, processID: nil))
        state.apply(HookEvent(sessionID: "s", turnID: "two", kind: "UserPromptSubmit", toolID: nil, toolName: nil, timestamp: 2, processID: nil))
        state.apply(HookEvent(sessionID: "s", turnID: "one", kind: "Stop", toolID: nil, toolName: nil, timestamp: 3, processID: nil))
        XCTAssertEqual(state.status, .working)
        state.apply(HookEvent(sessionID: "s", turnID: "two", kind: "PreToolUse", toolID: "input", toolName: "request_user_input", timestamp: 4, processID: nil))
        XCTAssertEqual(state.status, .needsInput)
        state.apply(HookEvent(sessionID: "s", turnID: "two", kind: "PostToolUse", toolID: "input", toolName: "request_user_input", timestamp: 5, processID: nil))
        XCTAssertEqual(state.status, .working)
        state.apply(HookEvent(sessionID: "s", turnID: "two", kind: "Stop", toolID: nil, toolName: nil, timestamp: 6, processID: nil))
        XCTAssertEqual(state.status, .idle)
    }

    func testFrameReaderAcceptsFragmentsAndMultipleFrames() throws {
        let a = try FrameBuffer.encode(.object(["method": .string("a")]))
        let b = try FrameBuffer.encode(.object(["method": .string("b")]))
        var reader = FrameBuffer()
        XCTAssertTrue(try reader.append(a.prefix(2)).isEmpty)
        let result = try reader.append(a.dropFirst(2) + b)
        XCTAssertEqual(result.map { $0["method"].string }, ["a", "b"])
        XCTAssertThrowsError(try reader.append(Data([0,0,0,0])))
    }
}
