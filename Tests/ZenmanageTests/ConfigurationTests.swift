import XCTest
@testable import Zenmanage

final class ConfigurationTests: XCTestCase {
    func testAcceptsMobileEnvironmentToken() throws {
        XCTAssertNoThrow(try ZenmanageConfiguration(environmentToken: "mob_live_123"))
    }

    func testAcceptsClientEnvironmentToken() throws {
        XCTAssertNoThrow(try ZenmanageConfiguration(environmentToken: "cli_live_123"))
    }

    func testRejectsServerEnvironmentToken() {
        XCTAssertThrowsError(try ZenmanageConfiguration(environmentToken: "srv_live_123")) { error in
            XCTAssertEqual(
                error as? ZenmanageError,
                .configuration("Invalid environment token for iOS runtime: server key provided. Use a mobile key (mob_...) or client key (cli_...).")
            )
        }
    }

    func testRejectsEnvironmentTokenWithAnUnknownPrefix() {
        XCTAssertThrowsError(try ZenmanageConfiguration(environmentToken: "live_123")) { error in
            XCTAssertEqual(
                error as? ZenmanageError,
                .configuration("Invalid environment token for iOS runtime. Use a mobile key (mob_...) or client key (cli_...).")
            )
        }
    }

    func testRejectsAnEmptyEnvironmentToken() {
        XCTAssertThrowsError(try ZenmanageConfiguration(environmentToken: "")) { error in
            XCTAssertEqual(error as? ZenmanageError, .configuration("Environment token is required"))
        }
    }

    func testRejectsANegativeCacheTTL() {
        XCTAssertThrowsError(try ZenmanageConfiguration(environmentToken: "mob_live_123", cacheTTL: -1)) { error in
            XCTAssertEqual(error as? ZenmanageError, .configuration("Cache TTL must be zero or greater"))
        }
    }

    func testUserDefaultsCacheExpiresEntries() throws {
        let suiteName = "zenmanage.swift.tests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let cache = UserDefaultsRuleCache(userDefaults: userDefaults, namespace: "tests")
        try cache.set("rules", value: "cached", ttl: 0)

        XCTAssertNil(try cache.get("rules"))
    }
}