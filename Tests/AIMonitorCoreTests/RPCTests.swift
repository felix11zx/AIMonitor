import XCTest
@testable import AIMonitorCore

final class RPCTests: XCTestCase {
    func testIdleConnectionProcessesLimitInvalidationWithoutPollingRead() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let executable=root.appendingPathComponent("codex-fixture")
        let script="""
        #!/usr/bin/env python3
        import json,sys,threading,time
        def invalidation():
            time.sleep(0.3)
            print(json.dumps({'method':'account/rateLimits/updated','params':{'rateLimits':{'limitId':'codex','primary':{'usedPercent':30}}}}),flush=True)
        for line in sys.stdin:
            request=json.loads(line)
            if 'id' not in request: continue
            result={} if request['method']=='initialize' else {'rateLimits':{'limitId':'codex','primary':{'usedPercent':20,'windowDurationMins':300}}}
            print(json.dumps({'id':request['id'],'result':result}),flush=True)
            if request['method']=='account/rateLimits/read': threading.Thread(target=invalidation,daemon=True).start()
        """
        try Data(script.utf8).write(to:executable)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:executable.path)
        let changed=expectation(description:"rate-limit update consumed while idle")
        let rpc=CodexRPC()
        let result=try await rpc.readLimits(executable:executable.path,home:root,onLimitsChanged:{ changed.fulfill() })
        XCTAssertEqual(result.windows.first?.remainingPercent,80)
        await fulfillment(of:[changed],timeout:3)
        await rpc.shutdown()
    }
}
