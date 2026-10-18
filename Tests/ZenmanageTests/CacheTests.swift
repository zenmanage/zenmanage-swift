import XCTest
@testable import Zenmanage

final class UserDefaultsRuleCacheTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var cache: UserDefaultsRuleCache!

    override func setUp() {
        super.setUp()
        suiteName = "com.zenmanage.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        cache = UserDefaultsRuleCache(userDefaults: defaults, namespace: "test.ns")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        cache = nil
        super.tearDown()
    }

    func testReturnsNilForAMissingKey() throws {
        XCTAssertNil(try cache.get("missing"))
    }

    func testStoresAndReturnsAValue() throws {
        try cache.set("rules", value: "{\"flags\":[]}", ttl: 60)

        XCTAssertEqual(try cache.get("rules"), "{\"flags\":[]}")
    }

    func testStoresValuesUnderTheNamespace() throws {
        try cache.set("rules", value: "v", ttl: 60)

        XCTAssertNotNil(defaults.data(forKey: "test.ns.rules"))
        XCTAssertNil(defaults.data(forKey: "rules"))
    }

    func testExpiredValueIsTreatedAsMissingAndRemoved() throws {
        try cache.set("rules", value: "stale", ttl: -10)

        XCTAssertNil(try cache.get("rules"))
        XCTAssertNil(defaults.data(forKey: "test.ns.rules"))
    }

    func testUndecodableEntryThrowsAndIsRemoved() {
        defaults.set(Data("not json".utf8), forKey: "test.ns.rules")

        XCTAssertThrowsError(try cache.get("rules")) { error in
            guard case ZenmanageError.cache = error else {
                return XCTFail("Expected a cache error, got \(error)")
            }
        }
        XCTAssertNil(defaults.data(forKey: "test.ns.rules"))
    }

    func testDeleteRemovesOnlyTheNamedKey() throws {
        try cache.set("a", value: "1", ttl: 60)
        try cache.set("b", value: "2", ttl: 60)

        try cache.delete("a")

        XCTAssertNil(try cache.get("a"))
        XCTAssertEqual(try cache.get("b"), "2")
    }

    func testClearRemovesEveryNamespacedKeyButLeavesOthersAlone() throws {
        try cache.set("a", value: "1", ttl: 60)
        try cache.set("b", value: "2", ttl: 60)
        defaults.set("keep me", forKey: "unrelated.key")

        try cache.clear()

        XCTAssertNil(try cache.get("a"))
        XCTAssertNil(try cache.get("b"))
        XCTAssertEqual(defaults.string(forKey: "unrelated.key"), "keep me")
    }

    func testNamespacesDoNotShareEntries() throws {
        let other = UserDefaultsRuleCache(userDefaults: defaults, namespace: "other.ns")

        try cache.set("rules", value: "mine", ttl: 60)

        XCTAssertNil(try other.get("rules"))
    }
}

final class InMemoryRuleCacheTests: XCTestCase {
    func testStoresAndReturnsAValue() throws {
        let cache = InMemoryRuleCache()

        try cache.set("rules", value: "v", ttl: 60)

        XCTAssertEqual(try cache.get("rules"), "v")
        XCTAssertNil(try cache.get("other"))
    }

    func testOverwritesAnExistingValue() throws {
        let cache = InMemoryRuleCache()

        try cache.set("rules", value: "old", ttl: 60)
        try cache.set("rules", value: "new", ttl: 60)

        XCTAssertEqual(try cache.get("rules"), "new")
    }

    func testExpiredValueIsTreatedAsMissing() throws {
        let cache = InMemoryRuleCache()

        try cache.set("rules", value: "stale", ttl: -1)

        XCTAssertNil(try cache.get("rules"))
    }

    func testDeleteAndClear() throws {
        let cache = InMemoryRuleCache()
        try cache.set("a", value: "1", ttl: 60)
        try cache.set("b", value: "2", ttl: 60)

        try cache.delete("a")
        XCTAssertNil(try cache.get("a"))
        XCTAssertEqual(try cache.get("b"), "2")

        try cache.clear()
        XCTAssertNil(try cache.get("b"))
    }
}

final class NullRuleCacheTests: XCTestCase {
    func testNeverStoresAnything() throws {
        let cache = NullRuleCache()

        try cache.set("rules", value: "v", ttl: 60)

        XCTAssertNil(try cache.get("rules"))
        XCTAssertNoThrow(try cache.delete("rules"))
        XCTAssertNoThrow(try cache.clear())
    }
}

/// A misbehaving cache: the SDK must keep serving flags when the cache can't be read from or
/// written to, rather than failing evaluation.
final class FlagManagerCacheFailureTests: XCTestCase {
    private struct BrokenCache: RuleCache {
        var stored: String?
        var failsToRead = false
        var failsToWrite = false

        func get(_ key: String) throws -> String? {
            if failsToRead { throw ZenmanageError.cache("read failed") }
            return stored
        }

        func set(_ key: String, value: String, ttl: TimeInterval) throws {
            if failsToWrite { throw ZenmanageError.cache("write failed") }
        }

        func delete(_ key: String) throws {}
        func clear() throws {}
    }

    override func tearDown() {
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.requestObserver = nil
        super.tearDown()
    }

    private func serveRules() {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSON())
        }
    }

    private func manager(cache: any RuleCache, logger: RecordingLogger) throws -> FlagManager {
        let configuration = try ZenmanageConfiguration(
            environmentToken: "mob_test_key",
            cache: cache,
            enableUsageReporting: false,
            logger: logger,
            urlSession: makeURLSession()
        )

        return Zenmanage(configuration: configuration).flags()
    }

    func testStillServesFlagsWhenTheCacheCannotBeWritten() async throws {
        serveRules()
        let logger = RecordingLogger()

        let flag = try await manager(cache: BrokenCache(failsToWrite: true), logger: logger)
            .single("checkout-flow")

        XCTAssertEqual(flag.asString(), "control")
    }

    func testFallsThroughToTheNetworkWhenTheCacheCannotBeRead() async throws {
        serveRules()

        let flag = try await manager(cache: BrokenCache(failsToRead: true), logger: RecordingLogger())
            .single("checkout-flow")

        XCTAssertEqual(flag.asString(), "control")
    }

    func testFallsThroughToTheNetworkWhenTheCachedPayloadIsGarbage() async throws {
        serveRules()

        let flag = try await manager(cache: BrokenCache(stored: "{ definitely not rules"), logger: RecordingLogger())
            .single("checkout-flow")

        XCTAssertEqual(flag.asString(), "control")
    }

    func testPrefersAValidCachedPayloadOverTheNetwork() async throws {
        URLProtocolMock.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let cached = String(decoding: makeRulesResponseJSON(), as: UTF8.self)

        let flag = try await manager(cache: BrokenCache(stored: cached), logger: RecordingLogger())
            .single("checkout-flow")

        XCTAssertEqual(flag.asString(), "control")
    }

    func testRefreshRulesBypassesTheCachedPayload() async throws {
        serveRules()
        let cache = InMemoryRuleCache()
        let flags = try manager(cache: cache, logger: RecordingLogger())

        _ = try await flags.single("new-ui")
        var requests = 0
        URLProtocolMock.requestObserver = { _ in requests += 1 }

        try await flags.refreshRules()

        XCTAssertEqual(requests, 2, "refreshRules() should fetch the metadata and the rules again")
    }
}
