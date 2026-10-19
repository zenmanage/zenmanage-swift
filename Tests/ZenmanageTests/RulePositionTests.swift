import XCTest
@testable import Zenmanage

/// Rules are evaluated lowest `position` first (first match wins). The payload isn't
/// guaranteed to arrive in that order, so the engine orders the rules itself.
final class RulePositionTests: XCTestCase {
    override func tearDown() {
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.requestObserver = nil
        super.tearDown()
    }

    private func rule(_ label: String, position: Int?, country: String = "US") -> Rule {
        Rule(
            version: label,
            clauses: [RuleCondition(attribute: "country", comparison: "equal", value: .string(country))],
            position: position,
            value: .string(label)
        )
    }

    private let usContext = Context(type: "user", identifier: "u1", attributes: [Attribute("country", values: ["US"])])

    func testOrderedKeepsPayloadOrderWhenNoRuleHasAPosition() {
        let rules = [rule("b", position: nil), rule("a", position: nil), rule("c", position: nil)]

        XCTAssertEqual(RuleEngine.ordered(rules).map(\.version), ["b", "a", "c"])
    }

    func testOrderedSortsByAscendingPosition() {
        let rules = [rule("third", position: 3), rule("first", position: 1), rule("second", position: 2)]

        XCTAssertEqual(RuleEngine.ordered(rules).map(\.version), ["first", "second", "third"])
    }

    func testOrderedKeepsPayloadOrderForRulesSharingAPosition() {
        let rules = [rule("x", position: 2), rule("y", position: 1), rule("z", position: 2), rule("w", position: 1)]

        XCTAssertEqual(RuleEngine.ordered(rules).map(\.version), ["y", "w", "x", "z"])
    }

    func testOrderedTreatsAMissingPositionAsZero() {
        let rules = [rule("positioned", position: 1), rule("unpositioned", position: nil)]

        XCTAssertEqual(RuleEngine.ordered(rules).map(\.version), ["unpositioned", "positioned"])
    }

    func testOrderedHandlesEmptyAndSingleRuleLists() {
        XCTAssertTrue(RuleEngine.ordered([]).isEmpty)
        XCTAssertEqual(RuleEngine.ordered([rule("only", position: 7)]).map(\.version), ["only"])
    }

    func testEvaluateReturnsTheLowestPositionMatchEvenWhenItArrivesLast() {
        let rules = [rule("late", position: 2), rule("early", position: 1)]

        XCTAssertEqual(RuleEngine().evaluate(rules, context: usContext)?.version, "early")
    }

    func testEvaluateSkipsAnEarlierPositionThatDoesNotMatch() {
        let rules = [rule("ca-first", position: 1, country: "CA"), rule("us-second", position: 2)]

        XCTAssertEqual(RuleEngine().evaluate(rules.reversed(), context: usContext)?.version, "us-second")
    }

    func testFlagManagerAppliesRulesInPositionOrderForTheWholePayload() async throws {
        let json = """
        {
          "version": "1",
          "flags": [
            {
              "version": "1", "type": "string", "key": "tier", "name": "Tier",
              "target": { "version": "1", "value": { "version": "1", "value": { "string": "base" } } },
              "rules": [
                {
                  "criteria": { "selector": "attribute", "selector_subtype": "country", "comparer": "equal", "values": ["US"] },
                  "position": 2,
                  "value": { "version": "1", "value": { "string": "second" } }
                },
                {
                  "criteria": { "selector": "attribute", "selector_subtype": "plan", "comparer": "equal", "values": ["free"] },
                  "position": 1,
                  "value": { "version": "1", "value": { "string": "first" } }
                }
              ]
            }
          ]
        }
        """
        URLProtocolMock.requestHandler = { request in
            if request.url?.host == "api.zenmanage.com" {
                return (makeHTTPResponse(url: request.url!), makeMetadataResponseJSON())
            }

            return (makeHTTPResponse(url: request.url!), Data(json.utf8))
        }

        let manager = Zenmanage(configuration: try makeConfiguration()).flags()
        let context = Context(
            type: "user", identifier: "u1",
            attributes: [Attribute("country", values: ["US"]), Attribute("plan", values: ["free"])]
        )

        let flag = try await manager.withContext(context).single("tier")
        XCTAssertEqual(flag.asString(), "first")
    }
}
