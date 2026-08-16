import XCTest
@testable import Zenmanage

final class ConfigurationTests: XCTestCase {
    func testAcceptsMobileEnvironmentToken() throws {
        XCTAssertNoThrow(try ZenmanageConfiguration(environmentToken: "mob_live_123"))
    }

    func testRejectsNonMobileEnvironmentToken() {
        XCTAssertThrowsError(try ZenmanageConfiguration(environmentToken: "cli_live_123")) { error in
            XCTAssertEqual(error as? ZenmanageError, .configuration("Invalid environment token for iOS runtime. Use a mobile key (mob_...) or server key (srv_...)."))
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