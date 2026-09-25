import XCTest
@testable import Zenmanage

/// Covers ZEN-1389: `json`-typed flags decode from the API's `{"json": ...}` wrapper
/// (both JSON object and JSON array shapes), `asJson()` follows the same "only recognizes
/// its own type, safe fallback otherwise" coercion pattern as `asBool`/`asString`/
/// `asNumber`, and Dictionary/Array defaults synthesize a `json`-typed flag instead of
/// being coerced to a string.
final class JsonFlagTypeTests: XCTestCase {
    // MARK: - Decoding a rules payload with json flags alongside other types

    func testDecodingRulesPayloadWithJsonFlagsAlongsideOtherTypesDoesNotThrow() throws {
        let decoder = JSONDecoder()

        let envelope = try decoder.decode(RulesEnvelope.self, from: makeRulesResponseJSONWithJsonFlags())

        XCTAssertEqual(envelope.flags.count, 4)

        let booleanFlag = try XCTUnwrap(envelope.flags.first(where: { $0.key == "new-ui" }))
        XCTAssertEqual(booleanFlag.type, .boolean)
        XCTAssertTrue(booleanFlag.asBool())

        let stringFlag = try XCTUnwrap(envelope.flags.first(where: { $0.key == "checkout-flow" }))
        XCTAssertEqual(stringFlag.type, .string)
        XCTAssertEqual(stringFlag.asString(), "control")

        let objectFlag = try XCTUnwrap(envelope.flags.first(where: { $0.key == "advanced-config" }))
        XCTAssertEqual(objectFlag.type, .json)
        XCTAssertEqual(objectFlag.asJson(), .object(["retries": .number(3), "endpoints": .array([.string("a"), .string("b")])]))

        let arrayFlag = try XCTUnwrap(envelope.flags.first(where: { $0.key == "allowed-regions" }))
        XCTAssertEqual(arrayFlag.type, .json)
        XCTAssertEqual(arrayFlag.asJson(), .array([.string("us"), .string("ca"), .string("gb")]))
    }

    func testAllIncludesJsonFlagsAlongsideOtherTypes() async throws {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSONWithJsonFlags())
        }
        defer {
            URLProtocolMock.requestHandler = nil
            URLProtocolMock.requestObserver = nil
        }

        let sdk = Zenmanage(configuration: try makeConfiguration())
        let allFlags = try await sdk.flags().all()

        XCTAssertEqual(allFlags.count, 4)
        XCTAssertTrue(allFlags.contains(where: { $0.key == "advanced-config" }))
        XCTAssertTrue(allFlags.contains(where: { $0.key == "allowed-regions" }))
    }

    func testSingleFetchesJsonFlagAlongsideOtherFlagsInSamePayload() async throws {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSONWithJsonFlags())
        }
        defer {
            URLProtocolMock.requestHandler = nil
            URLProtocolMock.requestObserver = nil
        }

        let sdk = Zenmanage(configuration: try makeConfiguration())

        let jsonFlag = try await sdk.flags().single("advanced-config")
        XCTAssertEqual(jsonFlag.type, .json)
        guard case let .object(fields) = jsonFlag.asJson() else {
            XCTFail("Expected advanced-config to decode as a JSON object")
            return
        }
        XCTAssertEqual(fields["retries"], .number(3))

        let numberFlag = try await sdk.flags().single("checkout-flow")
        XCTAssertEqual(numberFlag.asString(), "control")
    }

    // MARK: - asJson() cross-type coercion

    func testAsJsonOnJsonFlagWithObjectValueReturnsDecodedObject() {
        let flag = makeFlag(type: .json, value: .json(.object(["enabled": .boolean(true), "limit": .number(5)])))

        XCTAssertEqual(flag.asJson(), .object(["enabled": .boolean(true), "limit": .number(5)]))
    }

    func testAsJsonOnJsonFlagWithArrayValueReturnsDecodedArray() {
        let flag = makeFlag(type: .json, value: .json(.array([.string("beta"), .string("canary")])))

        XCTAssertEqual(flag.asJson(), .array([.string("beta"), .string("canary")]))
    }

    func testAsJsonOnJsonFlagWithBareScalarValueReturnsEmpty() {
        // The API allows a json flag's value to be a bare scalar (`{"json": 5}`), but real
        // flags won't normally use this. `asJson()` treats it as the safe-zero-value case,
        // the same as calling it on a non-json flag, rather than wrapping the scalar.
        let flag = makeFlag(type: .json, value: .json(.number(5)))

        XCTAssertEqual(flag.asJson(), .empty)
    }

    func testAsJsonOnNonJsonFlagsReturnsEmptyRatherThanThrowingOrConverting() {
        let booleanFlag = makeFlag(type: .boolean, value: .boolean(true))
        let stringFlag = makeFlag(type: .string, value: .string("hello"))
        let numberFlag = makeFlag(type: .number, value: .number(42))

        XCTAssertEqual(booleanFlag.asJson(), .empty)
        XCTAssertEqual(stringFlag.asJson(), .empty)
        XCTAssertEqual(numberFlag.asJson(), .empty)
    }

    func testAsBoolAsStringAsNumberOnJsonFlagFollowSafeFallbackPattern() {
        let flag = makeFlag(type: .json, value: .json(.object(["a": .number(1)])))

        // Mirrors the reference coercion table: a json flag's asBool() is unconditionally
        // true (like every other non-boolean type), and asString()/asNumber() fall back to
        // their safe zero values rather than attempting a lossy conversion.
        XCTAssertTrue(flag.asBool())
        XCTAssertEqual(flag.asString(), "")
        XCTAssertEqual(flag.asNumber(), 0)
        XCTAssertFalse(flag.isEnabled())
    }

    // MARK: - Default value typing

    func testDictionaryDefaultSynthesizesJsonTypedFlagNotStringifiedFallback() async throws {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSON())
        }
        defer {
            URLProtocolMock.requestHandler = nil
            URLProtocolMock.requestObserver = nil
        }

        let sdk = Zenmanage(configuration: try makeConfiguration())

        let defaultValue: JSONValue = ["theme": "dark", "max-items": 10]
        let flag = try await sdk.flags().single("missing-config", defaultValue: defaultValue)

        XCTAssertEqual(flag.type, .json)
        XCTAssertEqual(flag.asJson(), .object(["theme": .string("dark"), "max-items": .number(10)]))
        // A json default must never fall back to the string accessor's empty value.
        XCTAssertNotEqual(flag.asString(), "dark")
    }

    func testArrayDefaultSynthesizesJsonTypedFlag() async throws {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSON())
        }
        defer {
            URLProtocolMock.requestHandler = nil
            URLProtocolMock.requestObserver = nil
        }

        let sdk = Zenmanage(configuration: try makeConfiguration())

        let defaultValue: JSONValue = ["us", "ca"]
        let flag = try await sdk.flags().single("missing-regions", defaultValue: defaultValue)

        XCTAssertEqual(flag.type, .json)
        XCTAssertEqual(flag.asJson(), .array([.string("us"), .string("ca")]))
    }

    func testDefaultsCollectionJsonEntryResolvesToJsonTypedFlag() async throws {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSON())
        }
        defer {
            URLProtocolMock.requestHandler = nil
            URLProtocolMock.requestObserver = nil
        }

        let defaults = DefaultsCollection().set("missing-config", json: ["retries": 3])
        let sdk = Zenmanage(configuration: try makeConfiguration())

        let flag = try await sdk.flags().withDefaults(defaults).single("missing-config")

        XCTAssertEqual(flag.type, .json)
        XCTAssertEqual(flag.asJson(), .object(["retries": .number(3)]))
    }

    // MARK: - JSONValue round-trip

    func testJSONValueEncodesAndDecodesObjectAndArrayShapesThroughCacheRoundTrip() throws {
        let original: FlagValue = .json(.object(["retries": .number(3), "endpoints": .array([.string("a"), .string("b")]), "enabled": .boolean(true)]))

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FlagValue.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Test helpers

    private func makeFlag(type: FlagType, value: FlagValue) -> Flag {
        Flag(
            version: "1",
            type: type,
            key: "test-flag",
            name: "Test Flag",
            target: FlagTarget(version: "1", value: value)
        )
    }
}
