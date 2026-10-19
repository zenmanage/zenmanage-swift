import XCTest
@testable import Zenmanage

/// Covers the rules payload exactly as the Zenmanage CDN serves it: each rule carries a
/// `criteria` object of `selector` / `selector_subtype` / `comparer` / `values`, rather than
/// the `attribute` / `operator` / `value` clauses most of the other tests use. These are the
/// shapes the live API serves, kept here so a regression shows up offline.
final class CDNPayloadTests: XCTestCase {
    override func tearDown() {
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.requestObserver = nil
        super.tearDown()
    }

    // MARK: Fixture helpers

    private func rule(
        selector: String = "attribute",
        subtype: String?,
        comparer: String,
        values: String,
        position: Int = 1,
        result: Bool = true
    ) -> String {
        let subtypeJSON = subtype.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "version": "rul_\(UUID().uuidString)",
          "description": "rule",
          "criteria": {
            "selector": "\(selector)",
            "selector_subtype": \(subtypeJSON),
            "comparer": "\(comparer)",
            "values": \(values)
          },
          "position": \(position),
          "value": { "version": "val_rule", "value": { "boolean": \(result) } }
        }
        """
    }

    private func boolFlag(key: String, base: Bool = false, rules: [String]) -> String {
        """
        {
          "version": "fla_\(key)",
          "type": "boolean",
          "key": "\(key)",
          "name": "\(key)",
          "target": {
            "version": "tar_\(key)",
            "expired_at": null,
            "published_at": "2026-05-15T14:43:18+00:00",
            "scheduled_at": null,
            "value": { "version": "val_\(key)", "value": { "boolean": \(base) } }
          },
          "rules": [\(rules.joined(separator: ","))]
        }
        """
    }

    private func payload(_ flags: [String]) -> Data {
        Data("{\"version\":\"v1\",\"flags\":[\(flags.joined(separator: ","))]}".utf8)
    }

    private func serve(_ rules: Data) {
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), rules)
        }
    }

    private func flags(serving rules: Data, cache: any RuleCache = InMemoryRuleCache()) throws -> FlagManager {
        serve(rules)
        return Zenmanage(configuration: try makeConfiguration(cache: cache)).flags()
    }

    private func user(_ id: String, _ attributes: [Attribute] = []) -> Context {
        Context(type: "user", name: id, identifier: id, attributes: attributes)
    }

    private func enabled(_ manager: FlagManager, _ key: String, for context: Context) async throws -> Bool {
        try await manager.withContext(context).single(key).isEnabled()
    }

    // MARK: Attribute comparers

    func testAttributeComparersFollowTheServerSemantics() async throws {
        let manager = try flags(serving: payload([
            boolFlag(key: "plan-in", rules: [rule(subtype: "plan", comparer: "in", values: "[\"pro\",\"team\"]")]),
            boolFlag(key: "country-equal", rules: [rule(subtype: "country", comparer: "equal", values: "[\"US\"]")]),
            boolFlag(key: "plan-notequal", rules: [rule(subtype: "plan", comparer: "notequal", values: "[\"free\"]")]),
            boolFlag(key: "plan-notin", rules: [rule(subtype: "plan", comparer: "notin", values: "[\"free\",\"trial\"]")]),
            boolFlag(key: "tier-gte", rules: [rule(subtype: "tier", comparer: "gte", values: "[\"2\"]")]),
            boolFlag(key: "tier-gt", rules: [rule(subtype: "tier", comparer: "gt", values: "[\"1\"]")]),
            boolFlag(key: "age-lt", rules: [rule(subtype: "age", comparer: "lt", values: "[\"30\"]")]),
            boolFlag(key: "age-lte", rules: [rule(subtype: "age", comparer: "lte", values: "[\"42\"]")]),
            boolFlag(key: "tags-contains", rules: [rule(subtype: "tags", comparer: "contains", values: "[\"beta\"]")]),
            boolFlag(key: "tags-notcontains", rules: [rule(subtype: "tags", comparer: "notcontains", values: "[\"alpha\"]")]),
            boolFlag(key: "email-startswith", rules: [rule(subtype: "email", comparer: "startswith", values: "[\"admin\"]")]),
            boolFlag(key: "email-endswith", rules: [rule(subtype: "email", comparer: "endswith", values: "[\"@acme.com\"]")]),
            boolFlag(key: "email-notstartswith", rules: [rule(subtype: "email", comparer: "notstartswith", values: "[\"admin\"]")]),
            boolFlag(key: "email-notendswith", rules: [rule(subtype: "email", comparer: "notendswith", values: "[\"@acme.com\"]")]),
            boolFlag(key: "nickname-isnull", rules: [rule(subtype: "nickname", comparer: "isnull", values: "[]")]),
            boolFlag(key: "nickname-notnull", rules: [rule(subtype: "nickname", comparer: "notnull", values: "[]")]),
        ]))

        let alice = user("alice", [
            Attribute("country", values: ["US"]),
            Attribute("plan", values: ["free"]),
            Attribute("tier", values: ["1"]),
            Attribute("age", values: ["25"]),
            Attribute("tags", values: ["alpha", "beta"]),
            Attribute("email", values: ["alice@acme.com"]),
        ])
        let bob = user("bob", [
            Attribute("country", values: ["CA"]),
            Attribute("plan", values: ["pro"]),
            Attribute("tier", values: ["3"]),
            Attribute("age", values: ["42"]),
            Attribute("tags", values: ["gamma"]),
            Attribute("email", values: ["admin@acme.ca"]),
            Attribute("nickname", values: ["bobby"]),
        ])

        let expectations: [(String, Bool, Bool)] = [
            // key, alice, bob
            ("plan-in", false, true),
            ("country-equal", true, false),
            ("plan-notequal", false, true),
            ("plan-notin", false, true),
            ("tier-gte", false, true),
            ("tier-gt", false, true),
            ("age-lt", true, false),
            ("age-lte", true, true),
            ("tags-contains", true, false),
            ("tags-notcontains", false, true),
            ("email-startswith", false, true),
            ("email-endswith", true, false),
            ("email-notstartswith", true, false),
            ("email-notendswith", false, true),
            ("nickname-isnull", true, false),
            ("nickname-notnull", false, true),
        ]

        for (key, aliceExpected, bobExpected) in expectations {
            let aliceResult = try await enabled(manager, key, for: alice)
            let bobResult = try await enabled(manager, key, for: bob)
            XCTAssertEqual(aliceResult, aliceExpected, "\(key) for alice")
            XCTAssertEqual(bobResult, bobExpected, "\(key) for bob")
        }
    }

    func testMissingAttributeFollowsTheServerDefaults() async throws {
        let manager = try flags(serving: payload([
            boolFlag(key: "equal", rules: [rule(subtype: "country", comparer: "equal", values: "[\"US\"]")]),
            boolFlag(key: "in", rules: [rule(subtype: "country", comparer: "in", values: "[\"US\"]")]),
            boolFlag(key: "contains", rules: [rule(subtype: "country", comparer: "contains", values: "[\"U\"]")]),
            boolFlag(key: "gt", rules: [rule(subtype: "age", comparer: "gt", values: "[\"1\"]")]),
            boolFlag(key: "notnull", rules: [rule(subtype: "country", comparer: "notnull", values: "[]")]),
            boolFlag(key: "notequal", rules: [rule(subtype: "country", comparer: "notequal", values: "[\"US\"]")]),
            boolFlag(key: "notin", rules: [rule(subtype: "country", comparer: "notin", values: "[\"US\"]")]),
            boolFlag(key: "notcontains", rules: [rule(subtype: "country", comparer: "notcontains", values: "[\"U\"]")]),
            boolFlag(key: "isnull", rules: [rule(subtype: "country", comparer: "isnull", values: "[]")]),
        ]))
        let bare = user("bare")

        // With no matching attribute, positive comparers don't match and negative ones do.
        for key in ["equal", "in", "contains", "gt", "notnull"] {
            let result = try await enabled(manager, key, for: bare)
            XCTAssertFalse(result, key)
        }
        for key in ["notequal", "notin", "notcontains", "isnull"] {
            let result = try await enabled(manager, key, for: bare)
            XCTAssertTrue(result, key)
        }
    }

    func testNonNumericValuesNeverSatisfyNumericComparers() async throws {
        let manager = try flags(serving: payload([
            boolFlag(key: "tier-gt", rules: [rule(subtype: "tier", comparer: "gt", values: "[\"1\"]")]),
            boolFlag(key: "tier-bad-target", rules: [rule(subtype: "tier", comparer: "gt", values: "[\"abc\"]")]),
        ]))

        let notANumber = user("u1", [Attribute("tier", values: ["gold"])])
        let numeric = user("u2", [Attribute("tier", values: ["5"])])

        let notANumberGt = try await enabled(manager, "tier-gt", for: notANumber)
        let numericGt = try await enabled(manager, "tier-gt", for: numeric)
        let badTarget = try await enabled(manager, "tier-bad-target", for: numeric)
        XCTAssertFalse(notANumberGt)
        XCTAssertTrue(numericGt)
        XCTAssertFalse(badTarget)
    }

    // MARK: Context comparers

    func testContextComparersHonourTheOptionalType() async throws {
        let manager = try flags(serving: payload([
            boolFlag(key: "any-type", rules: [rule(
                selector: "context", subtype: nil, comparer: "equal",
                values: "[{\"identifier\":\"shared-123\",\"type\":null}]"
            )]),
            boolFlag(key: "org-only", rules: [rule(
                selector: "context", subtype: nil, comparer: "equal",
                values: "[{\"identifier\":\"shared-123\",\"type\":\"organization\"}]"
            )]),
            boolFlag(key: "not-user-ca", rules: [rule(
                selector: "context", subtype: nil, comparer: "notequal",
                values: "[{\"identifier\":\"user-ca-pro\",\"type\":null}]"
            )]),
        ]))

        let sharedUser = Context(type: "user", identifier: "shared-123")
        let sharedOrg = Context(type: "organization", identifier: "shared-123")
        let anonymous = Context(type: "anonymous")

        let anyTypeUser = try await enabled(manager, "any-type", for: sharedUser)
        let anyTypeOrg = try await enabled(manager, "any-type", for: sharedOrg)
        let orgOnlyUser = try await enabled(manager, "org-only", for: sharedUser)
        let orgOnlyOrg = try await enabled(manager, "org-only", for: sharedOrg)
        let orgOnlyAnonymous = try await enabled(manager, "org-only", for: anonymous)
        XCTAssertTrue(anyTypeUser)
        XCTAssertTrue(anyTypeOrg)
        XCTAssertFalse(orgOnlyUser)
        XCTAssertTrue(orgOnlyOrg)
        XCTAssertFalse(orgOnlyAnonymous)

        // A `notequal` rule matches everyone except the named identifier, who gets the base value.
        let excluded = try await enabled(manager, "not-user-ca", for: Context(type: "user", identifier: "user-ca-pro"))
        let everyoneElse = try await enabled(manager, "not-user-ca", for: Context(type: "user", identifier: "user-us-free"))
        XCTAssertFalse(excluded)
        XCTAssertTrue(everyoneElse)
    }

    // MARK: Decoding

    func testDecodesCDNMetadataAndCriteriaIntoConditions() throws {
        let data = payload([
            boolFlag(key: "plan-in", rules: [rule(subtype: "plan", comparer: "in", values: "[\"pro\"]")]),
            boolFlag(key: "ctx", rules: [rule(
                selector: "context", subtype: nil, comparer: "equal",
                values: "[{\"identifier\":\"user-1\",\"type\":null}]"
            )]),
        ])

        let envelope = try JSONDecoder().decode(RulesEnvelope.self, from: data)
        XCTAssertEqual(envelope.flags.count, 2)

        let planRule = try XCTUnwrap(envelope.flags[0].rules.first)
        XCTAssertEqual(planRule.position, 1)
        XCTAssertEqual(planRule.criteria?.attribute, "plan")
        XCTAssertEqual(planRule.criteria?.comparison, "in")
        XCTAssertEqual(planRule.criteria?.value, .strings(["pro"]))

        let contextRule = try XCTUnwrap(envelope.flags[1].rules.first)
        XCTAssertEqual(contextRule.criteria?.attribute, "context")
        XCTAssertEqual(contextRule.criteria?.value, .contextTargets([ContextTarget(identifier: "user-1")]))
    }

    // MARK: Cache round trip

    func testCachedRulesEvaluateTheSameAfterARoundTripThroughTheCache() async throws {
        let cache = InMemoryRuleCache()
        let rules = payload([
            boolFlag(key: "plan-in", rules: [rule(subtype: "plan", comparer: "in", values: "[\"pro\"]")]),
            boolFlag(key: "ctx", rules: [rule(
                selector: "context", subtype: nil, comparer: "equal",
                values: "[{\"identifier\":\"user-1\",\"type\":\"user\"}]"
            )]),
        ])

        let first = try flags(serving: rules, cache: cache)
        let pro = user("user-1", [Attribute("plan", values: ["pro"])])
        let firstPlan = try await enabled(first, "plan-in", for: pro)
        XCTAssertTrue(firstPlan)

        // A second client has to be served from the cache alone.
        URLProtocolMock.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let second = Zenmanage(configuration: try makeConfiguration(cache: cache)).flags()

        let secondPlan = try await enabled(second, "plan-in", for: pro)
        let secondFree = try await enabled(second, "plan-in", for: user("user-2", [Attribute("plan", values: ["free"])]))
        let secondContext = try await enabled(second, "ctx", for: pro)
        let secondOtherContext = try await enabled(second, "ctx", for: user("user-9"))
        XCTAssertTrue(secondPlan)
        XCTAssertFalse(secondFree)
        XCTAssertTrue(secondContext)
        XCTAssertFalse(secondOtherContext)
    }
}
