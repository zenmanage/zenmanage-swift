import XCTest
@testable import Zenmanage

/// Covers ZEN-1667: before the API can serve json flags, this SDK must tolerate an
/// unrecognized flag type/value in the rules payload instead of throwing away one flag
/// or the whole payload.
final class UnknownFlagTypeTests: XCTestCase {
    // MARK: - Decoding

    func testDecodingRulesPayloadWithUnknownFlagTypeDoesNotThrow() throws {
        let decoder = JSONDecoder()

        let envelope = try decoder.decode(RulesEnvelope.self, from: makeRulesResponseJSONWithUnknownFlag())

        XCTAssertEqual(envelope.flags.count, 4)

        guard let jsonFlag = envelope.flags.first(where: { $0.key == "advanced-config" }) else {
            XCTFail("Expected the json-typed flag to still be present in the decoded payload")
            return
        }

        XCTAssertEqual(jsonFlag.type, .unknown)
        XCTAssertEqual(jsonFlag.value, .unknown)

        let booleanFlag = try XCTUnwrap(envelope.flags.first(where: { $0.key == "new-ui" }))
        XCTAssertEqual(booleanFlag.type, .boolean)
        XCTAssertTrue(booleanFlag.asBool())

        let stringFlag = try XCTUnwrap(envelope.flags.first(where: { $0.key == "checkout-flow" }))
        XCTAssertEqual(stringFlag.type, .string)
        XCTAssertEqual(stringFlag.asString(), "control")

        let numberFlag = try XCTUnwrap(envelope.flags.first(where: { $0.key == "max-items" }))
        XCTAssertEqual(numberFlag.type, .number)
        XCTAssertEqual(numberFlag.asNumber(), 10)
    }

    func testDecodingUnrecognizedFlagTypeLogsOnce() throws {
        let logger = RecordingLogger()
        let decoder = JSONDecoder()
        decoder.userInfo[.zenmanageLogger] = logger

        _ = try decoder.decode(RulesEnvelope.self, from: makeRulesResponseJSONWithUnknownFlag())

        XCTAssertEqual(logger.warnings.count, 1)
        XCTAssertEqual(logger.warnings.first?.metadata?["type"], "json")
    }

    // MARK: - End-to-end evaluation through FlagManager

    func testOtherFlagsStillEvaluateAlongsideAnUnknownFlagType() async throws {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSONWithUnknownFlag())
        }
        defer {
            URLProtocolMock.requestHandler = nil
            URLProtocolMock.requestObserver = nil
        }

        let sdk = Zenmanage(configuration: try makeConfiguration())

        let booleanFlag = try await sdk.flags().single("new-ui")
        XCTAssertTrue(booleanFlag.isEnabled())

        let stringFlag = try await sdk.flags().single("checkout-flow")
        XCTAssertEqual(stringFlag.asString(), "control")

        let numberFlag = try await sdk.flags().single("max-items")
        XCTAssertEqual(numberFlag.asNumber(), 10)
    }

    func testUnknownFlagTypeResolvesToCallerSuppliedDefaultInsteadOfThrowing() async throws {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSONWithUnknownFlag())
        }
        defer {
            URLProtocolMock.requestHandler = nil
            URLProtocolMock.requestObserver = nil
        }

        let sdk = Zenmanage(configuration: try makeConfiguration())

        let flag = try await sdk.flags().single("advanced-config", defaultValue: false)

        XCTAssertFalse(flag.isEnabled())
        XCTAssertEqual(flag.asBool(), false)
    }

    func testUnknownFlagTypeResolvesToDefaultsCollectionValue() async throws {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSONWithUnknownFlag())
        }
        defer {
            URLProtocolMock.requestHandler = nil
            URLProtocolMock.requestObserver = nil
        }

        let defaults = DefaultsCollection().set("advanced-config", string: "fallback")
        let sdk = Zenmanage(configuration: try makeConfiguration())

        let flag = try await sdk.flags().withDefaults(defaults).single("advanced-config")

        XCTAssertEqual(flag.asString(), "fallback")
    }

    func testUnknownFlagTypeWithNoDefaultThrowsEvaluationErrorNotDecodingError() async throws {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSONWithUnknownFlag())
        }
        defer {
            URLProtocolMock.requestHandler = nil
            URLProtocolMock.requestObserver = nil
        }

        let sdk = Zenmanage(configuration: try makeConfiguration())

        do {
            _ = try await sdk.flags().single("advanced-config")
            XCTFail("Expected a missing-flag evaluation error")
        } catch let error as ZenmanageError {
            XCTAssertEqual(error, .evaluation("Flag not found: advanced-config"))
        }
    }

    func testAllOmitsFlagsWithUnknownType() async throws {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), makeRulesResponseJSONWithUnknownFlag())
        }
        defer {
            URLProtocolMock.requestHandler = nil
            URLProtocolMock.requestObserver = nil
        }

        let sdk = Zenmanage(configuration: try makeConfiguration())
        let allFlags = try await sdk.flags().all()

        XCTAssertEqual(allFlags.count, 3)
        XCTAssertFalse(allFlags.contains(where: { $0.key == "advanced-config" }))
    }
}

final class RecordingLogger: ZenmanageLogger {
    struct Entry {
        let message: String
        let metadata: [String: String]?
    }

    private let lock = NSLock()
    private var storedWarnings: [Entry] = []

    var warnings: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storedWarnings
    }

    func debug(_ message: String, metadata: [String: String]?) {}
    func info(_ message: String, metadata: [String: String]?) {}

    func warn(_ message: String, metadata: [String: String]?) {
        lock.lock()
        storedWarnings.append(Entry(message: message, metadata: metadata))
        lock.unlock()
    }

    func error(_ message: String, metadata: [String: String]?) {}
}
