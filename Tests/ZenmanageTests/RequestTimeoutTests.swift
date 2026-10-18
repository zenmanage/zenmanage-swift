import XCTest
@testable import Zenmanage

/// Every Zenmanage SDK gives up on a stuck request after 10 seconds (5 for the fire-and-forget
/// usage report) rather than inheriting the platform default, which for `URLSession` is 60
/// seconds per attempt, and the rules fetch retries three times.
final class RequestTimeoutTests: XCTestCase {
    private struct Observed {
        let path: String
        let timeout: TimeInterval
    }

    private var observed: [Observed] = []
    private let lock = NSLock()

    override func setUp() {
        super.setUp()
        observed = []
    }

    override func tearDown() {
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.requestObserver = nil
        super.tearDown()
    }

    private func timeouts(forPathsEndingIn suffix: String) -> [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return observed.filter { $0.path.hasSuffix(suffix) }.map(\.timeout)
    }

    private func serve(usageExpectation: XCTestExpectation? = nil) {
        URLProtocolMock.requestObserver = { [self] request in
            lock.lock()
            observed.append(Observed(path: request.url?.path ?? "", timeout: request.timeoutInterval))
            lock.unlock()

            if request.url?.path.hasSuffix("/usage") == true {
                usageExpectation?.fulfill()
            }
        }

        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com", request.url?.path == "/v1/flag-json" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            if request.url?.host == "cdn.example.com" {
                return (makeHTTPResponse(url: request.url!), makeRulesResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), Data())
        }
    }

    // MARK: Configuration

    func testDefaultsToTenSeconds() throws {
        let configuration = try makeConfiguration()

        XCTAssertEqual(configuration.requestTimeout, 10)
        XCTAssertEqual(ZenmanageConfiguration.defaultRequestTimeout, 10)
        XCTAssertEqual(ZenmanageConfiguration.usageReportTimeout, 5)
    }

    func testAcceptsACustomTimeout() throws {
        let configuration = try ZenmanageConfiguration(environmentToken: "mob_test_key", requestTimeout: 3)

        XCTAssertEqual(configuration.requestTimeout, 3)
    }

    func testRejectsAZeroOrNegativeTimeout() {
        for invalid in [0.0, -1.0] {
            XCTAssertThrowsError(try ZenmanageConfiguration(environmentToken: "mob_test_key", requestTimeout: invalid)) { error in
                XCTAssertEqual(error as? ZenmanageError, .configuration("Request timeout must be greater than zero"))
            }
        }
    }

    func testConvenienceInitializerPassesTheTimeoutThrough() async throws {
        serve()
        let sdk = try Zenmanage(
            environmentToken: "mob_test_key",
            cache: NullRuleCache(),
            enableUsageReporting: false,
            urlSession: makeURLSession(),
            requestTimeout: 4
        )

        _ = try await sdk.flags().single("new-ui")

        XCTAssertEqual(timeouts(forPathsEndingIn: "/v1/flag-json"), [4])
    }

    // MARK: Requests

    func testRulesRequestsUseTheDefaultTimeout() async throws {
        serve()
        let sdk = Zenmanage(configuration: try makeConfiguration())

        _ = try await sdk.flags().single("new-ui")

        XCTAssertEqual(timeouts(forPathsEndingIn: "/v1/flag-json"), [10])
        XCTAssertEqual(timeouts(forPathsEndingIn: "/rules.json"), [10])
    }

    func testRulesRequestsUseACustomTimeout() async throws {
        serve()
        let configuration = try ZenmanageConfiguration(
            environmentToken: "mob_test_key",
            cache: InMemoryRuleCache(),
            enableUsageReporting: false,
            urlSession: makeURLSession(),
            requestTimeout: 2.5
        )

        _ = try await Zenmanage(configuration: configuration).flags().single("new-ui")

        XCTAssertEqual(timeouts(forPathsEndingIn: "/v1/flag-json"), [2.5])
        XCTAssertEqual(timeouts(forPathsEndingIn: "/rules.json"), [2.5])
    }

    func testUsageReportsAreCappedAtFiveSeconds() async throws {
        let reported = expectation(description: "usage reported")
        serve(usageExpectation: reported)
        let sdk = Zenmanage(configuration: try makeConfiguration(enableUsageReporting: true))

        _ = try await sdk.flags().single("new-ui")
        await fulfillment(of: [reported], timeout: 2)

        XCTAssertEqual(timeouts(forPathsEndingIn: "/usage"), [5])
    }

    func testUsageReportsNeverExceedAShorterConfiguredTimeout() async throws {
        let reported = expectation(description: "usage reported")
        serve(usageExpectation: reported)
        let configuration = try ZenmanageConfiguration(
            environmentToken: "mob_test_key",
            cache: InMemoryRuleCache(),
            enableUsageReporting: true,
            urlSession: makeURLSession(),
            requestTimeout: 2
        )

        _ = try await Zenmanage(configuration: configuration).flags().single("new-ui")
        await fulfillment(of: [reported], timeout: 2)

        XCTAssertEqual(timeouts(forPathsEndingIn: "/usage"), [2])
    }
}
