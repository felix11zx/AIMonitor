import XCTest
@testable import AIMonitorCore

final class ReleaseTests: XCTestCase {
    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) throws -> GitHubRelease {
        let data = try JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": draft, "prerelease": prerelease])
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    func testNumericComparisonAndOptionalPrefix() throws {
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("v0.9.0")), try XCTUnwrap(ReleaseVersion("0.10.0")))
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("1.99.99")), try XCTUnwrap(ReleaseVersion("2.0.0")))
        XCTAssertEqual(ReleaseVersion("v0.2.0"), ReleaseVersion("0.2.0"))
        for value in ["", "1.2", "1.2.3.4", "1.2.3-beta", "../releases", "-1.2.3", "1..3", "1.2.3 "] {
            XCTAssertNil(ReleaseVersion(value), value)
        }
    }

    func testNewerReleaseLinksToOurRepository() throws {
        XCTAssertEqual(try ReleaseChecker.evaluate(release("v0.10.0"), currentVersion: "0.2.0"),
                       .available(version: "v0.10.0", url: URL(string: "https://github.com/felix11zx/AIMonitor/releases/tag/v0.10.0")!))
    }

    func testEqualAndOlderAreUpToDate() throws {
        XCTAssertEqual(try ReleaseChecker.evaluate(release("v0.2.0"), currentVersion: "0.2.0"), .upToDate)
        XCTAssertEqual(try ReleaseChecker.evaluate(release("v0.1.0"), currentVersion: "0.2.0"), .upToDate)
    }

    func testDraftsPrereleasesAndInvalidVersions() throws {
        XCTAssertEqual(try ReleaseChecker.evaluate(release("v1.0.0", draft: true), currentVersion: "0.2.0"), .noRelease)
        XCTAssertEqual(try ReleaseChecker.evaluate(release("v1.0.0-beta", prerelease: true), currentVersion: "0.2.0"), .noRelease)
        XCTAssertThrowsError(try ReleaseChecker.evaluate(release("latest"), currentVersion: "0.2.0"))
        XCTAssertThrowsError(try ReleaseChecker.evaluate(release("v0.3.0"), currentVersion: "unbekannt"))
    }

    func testHTTPResponsesAndRequestPrivacy() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let checker = ReleaseChecker()
        let current = try await checker.check(currentVersion: "0.2.0", session: session)
        let missing = try await checker.check(currentVersion: "missing", session: session)
        XCTAssertEqual(current, .upToDate)
        XCTAssertEqual(missing, .noRelease)
        for version in ["limited", "server", "malformed", "offline"] {
            do {
                _ = try await checker.check(currentVersion: version, session: session)
                XCTFail("Expected error for \(version)")
            } catch {
                if version == "limited" { XCTAssertTrue(error is ReleaseCheckError) }
            }
        }
    }
}

private final class ReleaseStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url, ReleaseChecker.endpoint)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        let agent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
        if agent.hasSuffix("offline") {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let status = agent.hasSuffix("missing") ? 404 : agent.hasSuffix("limited") ? 429 : agent.hasSuffix("server") ? 500 : 200
        let data = Data((agent.hasSuffix("malformed") ? "not json" : #"{"tag_name":"v0.2.0","draft":false,"prerelease":false}"#).utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
