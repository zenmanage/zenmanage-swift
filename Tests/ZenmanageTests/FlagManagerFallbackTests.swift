import XCTest
@testable import Zenmanage

/// Covers ZEN-1746: `single()` must fall back to the caller-provided default (or a
/// `DefaultsCollection` entry) instead of throwing when the rules fetch fails outright —
/// e.g. an invalid or unreachable environment token. `refreshRules()`, by contrast, is an
/// explicit refresh and should still surface its own failure.
final class FlagManagerFallbackTests: XCTestCase {
    override func tearDown() {
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.requestObserver = nil
        super.tearDown()
    }

    private func makeUnreachableConfiguration() throws -> ZenmanageConfiguration {
        URLProtocolMock.requestHandler = { request in
            (makeHTTPResponse(url: request.url!, statusCode: 401), Data())
        }

        return try makeConfiguration(environmentToken: "mob_invalid_env_key")
    }

    func testSingleFallsBackToInlineDefaultWhenEnvironmentUnreachable() async throws {
        let sdk = Zenmanage(configuration: try makeUnreachableConfiguration())

        let flag = try await sdk.flags().single("some-flag", defaultValue: true)

        XCTAssertTrue(flag.isEnabled())
    }

    func testSingleFallsBackToDefaultsCollectionWhenEnvironmentUnreachable() async throws {
        let defaults = DefaultsCollection().set("fallback-flag", string: "control")
        let sdk = Zenmanage(configuration: try makeUnreachableConfiguration())

        let flag = try await sdk.flags().withDefaults(defaults).single("fallback-flag")

        XCTAssertEqual(flag.asString(), "control")
    }

    func testSingleStillThrowsWhenEnvironmentUnreachableAndNoDefaultProvided() async throws {
        let sdk = Zenmanage(configuration: try makeUnreachableConfiguration())

        do {
            _ = try await sdk.flags().single("no-default-flag")
            XCTFail("Expected single() to throw when no default is available")
        } catch {
            // Expected: falling back to defaults only helps when a default exists.
        }
    }

    func testRefreshRulesStillThrowsWhenEnvironmentUnreachable() async throws {
        let sdk = Zenmanage(configuration: try makeUnreachableConfiguration())

        do {
            try await sdk.flags().refreshRules()
            XCTFail("Expected refreshRules() to surface the fetch failure")
        } catch {
            // Expected: an explicit refresh should still surface its own failure.
        }
    }
}
