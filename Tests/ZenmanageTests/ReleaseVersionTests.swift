import XCTest
@testable import Zenmanage

/// The version appears in two places: `ZenmanageSDK.version` (sent to the API) and
/// `CHANGELOG.md`. They used to be updated by hand and had no check, so the client agent
/// header could report a version that was never released.
final class ReleaseVersionTests: XCTestCase {
    override func tearDown() {
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.requestObserver = nil
        super.tearDown()
    }

    private func repositoryFile(_ name: String) throws -> String {
        // Tests/ZenmanageTests/<this file> -> repository root
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let url = root.appendingPathComponent(name)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "\(name) isn't available from this test run")

        return try String(contentsOf: url, encoding: .utf8)
    }

    func testVersionIsAThreePartSemanticVersion() {
        let parts = ZenmanageSDK.version.split(separator: ".", omittingEmptySubsequences: false)

        XCTAssertEqual(parts.count, 3, ZenmanageSDK.version)
        XCTAssertTrue(parts.allSatisfy { Int($0) != nil }, ZenmanageSDK.version)
    }

    func testChangelogHasAReleasedSectionForTheSDKVersion() throws {
        let changelog = try repositoryFile("CHANGELOG.md")

        XCTAssertTrue(
            changelog.contains("## [\(ZenmanageSDK.version)] - "),
            "CHANGELOG.md needs a dated '## [\(ZenmanageSDK.version)] - YYYY-MM-DD' section"
        )
    }

    func testRequestsReportTheSDKVersionInTheClientAgent() async throws {
        var agents: [String] = []
        let lock = NSLock()
        URLProtocolMock.requestObserver = { request in
            lock.lock()
            agents.append(request.value(forHTTPHeaderField: "X-ZEN-CLIENT-AGENT") ?? "")
            lock.unlock()
        }
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSON())
        }

        _ = try await Zenmanage(configuration: try makeConfiguration()).flags().single("new-ui")

        lock.lock()
        defer { lock.unlock() }
        XCTAssertFalse(agents.isEmpty)
        XCTAssertTrue(agents.allSatisfy { $0 == "zenmanage-swift/\(ZenmanageSDK.version)" }, "\(agents)")
    }

    func testAClientAgentOverrideKeepsTheSDKVersion() async throws {
        var agent = ""
        let lock = NSLock()
        URLProtocolMock.requestObserver = { request in
            lock.lock()
            agent = request.value(forHTTPHeaderField: "X-ZEN-CLIENT-AGENT") ?? ""
            lock.unlock()
        }
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSON())
        }
        let configuration = try ZenmanageConfiguration(
            environmentToken: "mob_test_key",
            cache: InMemoryRuleCache(),
            enableUsageReporting: false,
            urlSession: makeURLSession(),
            clientAgent: "zenmanage-wrapper"
        )

        _ = try await Zenmanage(configuration: configuration).flags().single("new-ui")

        lock.lock()
        defer { lock.unlock() }
        XCTAssertEqual(agent, "zenmanage-wrapper/\(ZenmanageSDK.version)")
    }
}
