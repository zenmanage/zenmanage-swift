import XCTest
@testable import Zenmanage

final class ZenmanageClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.requestObserver = nil
        super.tearDown()
    }

    func testLoadsRulesAndEvaluatesContextRule() async throws {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSON())
        }

        let sdk = Zenmanage(configuration: try makeConfiguration())
        let context = Context(type: "user", identifier: "user-123", attributes: [Attribute("country", values: ["US"])])

        let flag = try await sdk.flags().withContext(context).single("new-ui")
        XCTAssertTrue(flag.isEnabled())
    }

    func testUsesSharedCacheAcrossClientInstances() async throws {
        var requestCount = 0
        URLProtocolMock.requestHandler = { request in
            requestCount += 1

            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSON())
        }

        let cache = InMemoryRuleCache()
        let firstSDK = Zenmanage(configuration: try makeConfiguration(cache: cache))
        _ = try await firstSDK.flags().single("new-ui")

        let secondSDK = Zenmanage(configuration: try makeConfiguration(cache: cache))
        let secondFlag = try await secondSDK.flags().single("new-ui")

        XCTAssertFalse(secondFlag.isEnabled())
        XCTAssertEqual(requestCount, 2)
    }

    func testUsesDefaultsWhenFlagIsMissing() async throws {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            let emptyRules = Data("{\"version\":\"1\",\"flags\":[]}".utf8)
            return (makeHTTPResponse(url: request.url!), emptyRules)
        }

        let defaults = DefaultsCollection()
            .set("fallback-flag", bool: true)

        let sdk = Zenmanage(configuration: try makeConfiguration())
        let flag = try await sdk.flags().withDefaults(defaults).single("fallback-flag")

        XCTAssertTrue(flag.isEnabled())
    }

    func testEvaluatesRolloutTargetAndRules() async throws {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSON())
        }

        let context = Context(type: "user", identifier: "user-1", attributes: [Attribute("country", values: ["US"])])
        let sdk = Zenmanage(configuration: try makeConfiguration())

        let flag = try await sdk.flags().withContext(context).single("checkout-flow")
        XCTAssertEqual(flag.asString(), "one-page-us")
    }

    func testReportsUsageWithContextHeader() async throws {
        let usageExpectation = expectation(description: "Usage reported")

        URLProtocolMock.requestObserver = { request in
            if request.url?.path == "/v1/flags/new-ui/usage" {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertNotNil(request.value(forHTTPHeaderField: "X-ZEN-CONTEXT"))
                usageExpectation.fulfill()
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

        let sdk = Zenmanage(configuration: try makeConfiguration(enableUsageReporting: true))
        let context = Context(type: "user", identifier: "user-usage", attributes: [Attribute("country", values: ["US"])])

        _ = try await sdk.flags().withContext(context).single("new-ui")
        await fulfillment(of: [usageExpectation], timeout: 2.0)
    }

    func testReportsUsageWithDefaultValueHeaderWhenFlagMissing() async throws {
        let usageExpectation = expectation(description: "Usage reported with inline default value")

        URLProtocolMock.requestObserver = { request in
            if request.url?.path == "/v1/flags/missing-flag/usage" {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-ZEN-DEFAULT-VALUE"), "{\"missing-flag\":true}")
                usageExpectation.fulfill()
            }
        }

        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com", request.url?.path == "/v1/flag-json" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            if request.url?.host == "cdn.example.com" {
                let emptyRules = Data("{\"version\":\"1\",\"flags\":[]}".utf8)
                return (makeHTTPResponse(url: request.url!), emptyRules)
            }

            return (makeHTTPResponse(url: request.url!), Data())
        }

        let sdk = Zenmanage(configuration: try makeConfiguration(enableUsageReporting: true))
        _ = try await sdk.flags().single("missing-flag", defaultValue: true)

        await fulfillment(of: [usageExpectation], timeout: 2.0)
    }

    func testReportsUsageWithDefaultValueHeaderFromDefaultsCollection() async throws {
        let usageExpectation = expectation(description: "Usage reported with defaults-collection value")

        URLProtocolMock.requestObserver = { request in
            if request.url?.path == "/v1/flags/fallback-flag/usage" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-ZEN-DEFAULT-VALUE"), "{\"fallback-flag\":\"control\"}")
                usageExpectation.fulfill()
            }
        }

        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com", request.url?.path == "/v1/flag-json" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            if request.url?.host == "cdn.example.com" {
                let emptyRules = Data("{\"version\":\"1\",\"flags\":[]}".utf8)
                return (makeHTTPResponse(url: request.url!), emptyRules)
            }

            return (makeHTTPResponse(url: request.url!), Data())
        }

        let defaults = DefaultsCollection().set("fallback-flag", string: "control")
        let sdk = Zenmanage(configuration: try makeConfiguration(enableUsageReporting: true))
        _ = try await sdk.flags().withDefaults(defaults).single("fallback-flag")

        await fulfillment(of: [usageExpectation], timeout: 2.0)
    }

    func testReportsUsageWithNumberDefaultValueHeader() async throws {
        let usageExpectation = expectation(description: "Usage reported with number default value")

        URLProtocolMock.requestObserver = { request in
            if request.url?.path == "/v1/flags/num-flag/usage" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-ZEN-DEFAULT-VALUE"), "{\"num-flag\":42}")
                usageExpectation.fulfill()
            }
        }

        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com", request.url?.path == "/v1/flag-json" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            if request.url?.host == "cdn.example.com" {
                let emptyRules = Data("{\"version\":\"1\",\"flags\":[]}".utf8)
                return (makeHTTPResponse(url: request.url!), emptyRules)
            }

            return (makeHTTPResponse(url: request.url!), Data())
        }

        let sdk = Zenmanage(configuration: try makeConfiguration(enableUsageReporting: true))
        _ = try await sdk.flags().single("num-flag", defaultValue: 42)

        await fulfillment(of: [usageExpectation], timeout: 2.0)
    }

    func testReportsUsageWithoutDefaultValueHeaderWhenFlagFound() async throws {
        let usageExpectation = expectation(description: "Usage reported without default value")

        URLProtocolMock.requestObserver = { request in
            if request.url?.path == "/v1/flags/new-ui/usage" {
                XCTAssertNil(request.value(forHTTPHeaderField: "X-ZEN-DEFAULT-VALUE"))
                usageExpectation.fulfill()
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

        let sdk = Zenmanage(configuration: try makeConfiguration(enableUsageReporting: true))
        _ = try await sdk.flags().single("new-ui")

        await fulfillment(of: [usageExpectation], timeout: 2.0)
    }

    func testObjectiveCWrapperInitializes() throws {
        XCTAssertNoThrow(try ObjCZenmanage(environmentToken: "mob_test_key"))
    }
}