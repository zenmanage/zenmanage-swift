import XCTest
@testable import Zenmanage

final class ObjectiveCBridgeTests: XCTestCase {
    override func tearDown() {
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.requestObserver = nil
        super.tearDown()
    }

    // MARK: Helpers

    private func serveRules(_ rules: Data = makeRulesResponseJSON(), failing: Bool = false) {
        URLProtocolMock.requestHandler = { request in
            if failing {
                return (makeHTTPResponse(url: request.url!, statusCode: 401), Data())
            }

            if request.url?.host == "api.zenmanage.com", request.url?.path == "/v1/flag-json" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            if request.url?.host == "cdn.example.com" {
                return (makeHTTPResponse(url: request.url!), rules)
            }

            return (makeHTTPResponse(url: request.url!), Data())
        }
    }

    private func makeManager(enableUsageReporting: Bool = false) throws -> ObjCFlagManager {
        let sdk = Zenmanage(configuration: try makeConfiguration(enableUsageReporting: enableUsageReporting))
        return ObjCFlagManager(manager: sdk.flags())
    }

    private func single(
        _ manager: ObjCFlagManager,
        _ key: String,
        defaultValue: NSObject? = nil,
        context: ObjCContext? = nil
    ) async -> (flag: ObjCFlag?, error: NSError?) {
        await withCheckedContinuation { continuation in
            manager.single(key, defaultValue: defaultValue, context: context) { flag, error in
                continuation.resume(returning: (flag, error))
            }
        }
    }

    private func all(_ manager: ObjCFlagManager, context: ObjCContext? = nil) async -> (flags: [ObjCFlag]?, error: NSError?) {
        await withCheckedContinuation { continuation in
            manager.allWithContext(context) { flags, error in
                continuation.resume(returning: (flags, error))
            }
        }
    }

    private func refresh(_ manager: ObjCFlagManager) async -> NSError? {
        await withCheckedContinuation { continuation in
            manager.refreshRulesWithCompletion { error in
                continuation.resume(returning: error)
            }
        }
    }

    // MARK: Value types

    func testAttributeAndContextWrappersExposeTheirFields() {
        let attribute = ObjCAttribute(key: "country", values: ["US"])
        let context = ObjCContext(type: "user", name: "Una", identifier: "u1", attributes: [attribute])

        XCTAssertEqual(attribute.key, "country")
        XCTAssertEqual(attribute.values, ["US"])
        XCTAssertEqual(context.type, "user")
        XCTAssertEqual(context.name, "Una")
        XCTAssertEqual(context.identifier, "u1")
        XCTAssertEqual(context.attributes.count, 1)
        XCTAssertEqual(context.context.attribute(forKey: "country")?.values, ["US"])
    }

    func testSingleContextFactory() {
        let context = ObjCContext.single(type: "user", identifier: "u1", name: "Una")

        XCTAssertEqual(context.identifier, "u1")
        XCTAssertEqual(context.name, "Una")
        XCTAssertTrue(context.attributes.isEmpty)
    }

    func testDefaultsCollectionIsChainable() {
        let defaults = ObjCDefaultsCollection()
            .setBool(true, forKey: "bool")
            .setString("s", forKey: "string")
            .setNumber(NSNumber(value: 4.5), forKey: "number")
            .setJson(["a": 1] as NSDictionary, forKey: "object")
            .setJson([1, 2] as NSArray, forKey: "array")

        XCTAssertEqual(defaults.defaults.get("bool"), .boolean(true))
        XCTAssertEqual(defaults.defaults.get("string"), .string("s"))
        XCTAssertEqual(defaults.defaults.get("number"), .number(4.5))
        XCTAssertEqual(defaults.defaults.get("object"), .json(["a": 1]))
        XCTAssertEqual(defaults.defaults.get("array"), .json([1, 2]))
    }

    func testSetJsonIgnoresValuesThatAreNotAContainer() {
        let defaults = ObjCDefaultsCollection()
            .setJson("just a string", forKey: "string")
            .setJson(NSNumber(value: 5), forKey: "number")
            .setJson(NSNull(), forKey: "null")

        XCTAssertEqual(defaults.defaults.size(), 0)
    }

    func testFlagWrapperExposesTheAccessors() {
        let flag = ObjCFlag(flag: Flag(
            version: "1", type: .json, key: "config", name: "Config",
            target: FlagTarget(value: .json(["retries": 3]))
        ))

        XCTAssertEqual(flag.key, "config")
        XCTAssertEqual(flag.name, "Config")
        XCTAssertEqual(flag.type, "json")
        XCTAssertFalse(flag.isEnabled())
        XCTAssertTrue(flag.asBool())
        XCTAssertEqual(flag.asString(), "")
        XCTAssertEqual(flag.asNumber(), 0)
        XCTAssertEqual(flag.asJson() as? NSDictionary, ["retries": 3])
    }

    // MARK: Foundation <-> JSONValue

    func testJSONValueConvertsFromFoundationObjects() {
        let object: NSDictionary = [
            "string": "s",
            "int": 3,
            "double": 1.5,
            "yes": true,
            "no": false,
            "nothing": NSNull(),
            "list": [1, "two"],
            "nested": ["a": ["b": 1]],
        ]

        let value = JSONValue(foundationValue: object)

        XCTAssertEqual(value, [
            "string": "s",
            "int": 3,
            "double": 1.5,
            "yes": true,
            "no": false,
            "nothing": nil,
            "list": [1, "two"],
            "nested": ["a": ["b": 1]],
        ])
    }

    func testBooleansStayBooleansAndNumbersStayNumbers() {
        XCTAssertEqual(JSONValue(foundationValue: NSNumber(value: true)), .boolean(true))
        XCTAssertEqual(JSONValue(foundationValue: NSNumber(value: 1)), .number(1))
        XCTAssertEqual(JSONValue(foundationValue: NSNumber(value: 0)), .number(0))
    }

    func testUnrepresentableFoundationValuesBecomeNull() {
        XCTAssertEqual(JSONValue(foundationValue: Date()), .null)
        XCTAssertEqual(JSONValue(foundationValue: ["when": Date()] as NSDictionary), ["when": nil])
    }

    func testFoundationRoundTrip() {
        let original: JSONValue = ["a": [1, true, nil, "x"], "b": ["c": 2.5]]

        XCTAssertEqual(JSONValue(foundationValue: original.foundationValue), original)
    }

    // MARK: Flag manager

    func testSingleReturnsAFlagFromTheRules() async throws {
        serveRules()
        let manager = try makeManager()

        let result = await single(manager, "checkout-flow")

        XCTAssertNil(result.error)
        XCTAssertEqual(result.flag?.asString(), "control")
        XCTAssertEqual(result.flag?.type, "string")
    }

    func testSingleEvaluatesWithTheSuppliedContext() async throws {
        serveRules()
        let manager = try makeManager()
        let context = ObjCContext(
            type: "user", identifier: "u1",
            attributes: [ObjCAttribute(key: "country", values: ["US"])]
        )

        let withContext = await single(manager, "new-ui", context: context)
        let withoutContext = await single(manager, "new-ui")

        XCTAssertEqual(withContext.flag?.isEnabled(), true)
        XCTAssertEqual(withoutContext.flag?.isEnabled(), false)
    }

    func testSingleFallsBackToEachSupportedDefaultKind() async throws {
        serveRules()
        let manager = try makeManager()

        let string = await single(manager, "missing", defaultValue: "fallback" as NSString)
        let bool = await single(manager, "missing", defaultValue: NSNumber(value: true))
        let double = await single(manager, "missing", defaultValue: NSNumber(value: 2.5))
        let object = await single(manager, "missing", defaultValue: ["a": 1] as NSDictionary)
        let array = await single(manager, "missing", defaultValue: [1, 2] as NSArray)

        XCTAssertEqual(string.flag?.asString(), "fallback")
        XCTAssertEqual(bool.flag?.isEnabled(), true)
        XCTAssertEqual(bool.flag?.type, "boolean")
        XCTAssertEqual(double.flag?.asNumber(), 2.5)
        XCTAssertEqual(double.flag?.type, "number")
        XCTAssertEqual(object.flag?.asJson() as? NSDictionary, ["a": 1])
        XCTAssertEqual(object.flag?.type, "json")
        XCTAssertEqual(array.flag?.asJson() as? NSArray, [1, 2])
        XCTAssertEqual(array.flag?.type, "json")
    }

    func testSingleReportsAnErrorForAnUnsupportedDefault() async throws {
        serveRules()
        let manager = try makeManager()

        let result = await single(manager, "missing", defaultValue: NSDate())

        XCTAssertNil(result.flag)
        XCTAssertEqual(result.error?.domain, "com.zenmanage.swift")
        XCTAssertEqual(result.error?.code, 1001)
        XCTAssertEqual(
            result.error?.localizedDescription,
            "Objective-C defaults must be NSString, NSNumber, NSDictionary, or NSArray"
        )
    }

    func testSingleReportsAnEvaluationErrorWhenThereIsNoFlagAndNoDefault() async throws {
        serveRules()
        let manager = try makeManager()

        let result = await single(manager, "missing")

        XCTAssertNil(result.flag)
        XCTAssertEqual(result.error?.code, 1002)
    }

    func testWithDefaultsSuppliesFlagsThatAreMissingFromTheRules() async throws {
        serveRules()
        let manager = try makeManager()
        let defaults = ObjCDefaultsCollection()
            .setJson(["limit": 10] as NSDictionary, forKey: "config")

        let result = await single(manager.withDefaults(defaults), "config")

        XCTAssertEqual(result.flag?.asJson() as? NSDictionary, ["limit": 10])
    }

    func testWithContextReturnsAScopedManager() async throws {
        serveRules()
        let manager = try makeManager().withContext(ObjCContext(
            type: "user", identifier: "u1",
            attributes: [ObjCAttribute(key: "country", values: ["US"])]
        ))

        let result = await single(manager, "new-ui")

        XCTAssertEqual(result.flag?.isEnabled(), true)
    }

    func testAllReturnsEveryFlag() async throws {
        serveRules()
        let manager = try makeManager()

        let result = await all(manager)

        XCTAssertNil(result.error)
        XCTAssertEqual(Set(result.flags?.map(\.key) ?? []), ["new-ui", "checkout-flow"])
    }

    func testAllEvaluatesWithTheSuppliedContext() async throws {
        serveRules()
        let manager = try makeManager()
        let context = ObjCContext(
            type: "user", identifier: "u1",
            attributes: [ObjCAttribute(key: "country", values: ["US"])]
        )

        let result = await all(manager, context: context)

        XCTAssertEqual(result.flags?.first(where: { $0.key == "new-ui" })?.isEnabled(), true)
    }

    func testAllReportsAnErrorWhenTheRulesCannotBeLoaded() async throws {
        serveRules(failing: true)
        let manager = try makeManager()

        let result = await all(manager)

        XCTAssertNil(result.flags)
        XCTAssertEqual(result.error?.code, 1003)
    }

    func testRefreshRulesCompletesWithoutAnErrorOnSuccess() async throws {
        serveRules()
        let manager = try makeManager()

        let error = await refresh(manager)

        XCTAssertNil(error)
    }

    func testRefreshRulesSurfacesAFailure() async throws {
        serveRules(failing: true)
        let manager = try makeManager()

        let error = await refresh(manager)

        XCTAssertEqual(error?.domain, "com.zenmanage.swift")
        XCTAssertEqual(error?.code, 1003)
    }

    func testReportUsageSendsTheContext() async throws {
        let reported = expectation(description: "usage reported")
        URLProtocolMock.requestObserver = { request in
            guard request.url?.path == "/v1/flags/new-ui/usage" else { return }

            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-ZEN-CONTEXT"))
            reported.fulfill()
        }
        serveRules()
        let manager = try makeManager(enableUsageReporting: true)

        manager.reportUsage("new-ui", context: ObjCContext.single(type: "user", identifier: "u1"))

        await fulfillment(of: [reported], timeout: 2)
    }

    func testReportUsageWithoutAContextOmitsTheContextHeader() async throws {
        let reported = expectation(description: "usage reported")
        URLProtocolMock.requestObserver = { request in
            guard request.url?.path == "/v1/flags/new-ui/usage" else { return }

            XCTAssertNil(request.value(forHTTPHeaderField: "X-ZEN-CONTEXT"))
            reported.fulfill()
        }
        serveRules()
        let manager = try makeManager(enableUsageReporting: true)

        manager.reportUsage("new-ui", context: nil)

        await fulfillment(of: [reported], timeout: 2)
    }

    // MARK: Entry point

    func testInitializerRejectsAnInvalidEndpoint() {
        XCTAssertThrowsError(try ObjCZenmanage(
            environmentToken: "mob_test_key",
            cacheTTL: 60,
            enableUsageReporting: false,
            apiEndpoint: ""
        ))
    }

    func testInitializerRejectsAServerToken() {
        XCTAssertThrowsError(try ObjCZenmanage(
            environmentToken: "srv_not_for_an_app",
            cacheTTL: 60,
            enableUsageReporting: false,
            apiEndpoint: "https://api.zenmanage.com"
        ))
    }

    func testEntryPointVendsAFlagManager() throws {
        let sdk = try ObjCZenmanage(
            environmentToken: "mob_test_key",
            cacheTTL: 60,
            enableUsageReporting: false,
            apiEndpoint: "https://api.zenmanage.com"
        )

        XCTAssertNotNil(sdk.flags())
    }
}
