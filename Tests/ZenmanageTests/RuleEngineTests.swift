import XCTest
@testable import Zenmanage

final class RuleEngineTests: XCTestCase {
    func testEvaluatesAttributeClauses() {
        let engine = RuleEngine()
        let context = Context(
            type: "user",
            identifier: "user-123",
            attributes: [
                Attribute("country", values: ["US"]),
                Attribute("plan", values: ["pro"]),
                Attribute("age", values: ["21"]),
            ]
        )

        let rule = Rule(
            clauses: [
                RuleCondition(attribute: "country", comparison: "equal", value: .string("US")),
                RuleCondition(attribute: "age", comparison: "gte", value: .string("18")),
            ],
            value: .boolean(true)
        )

        XCTAssertEqual(engine.evaluate([rule], context: context)?.value, .boolean(true))
    }

    func testEvaluatesContextTargetsByType() {
        let engine = RuleEngine()
        let context = Context(type: "organization", identifier: "org-123")

        let rule = Rule(
            criteria: RuleCondition(
                attribute: "context",
                comparison: "equal",
                value: .contextTargets([
                    ContextTarget(identifier: "org-123", type: "organization"),
                    ContextTarget(identifier: "user-123", type: "user"),
                ])
            ),
            value: .string("matched")
        )

        XCTAssertEqual(engine.evaluate([rule], context: context)?.value, .string("matched"))
    }

    func testEvaluatesContainsClause() {
        let engine = RuleEngine()
        let context = Context(
            type: "user",
            identifier: "user-123",
            attributes: [
                Attribute("email", values: ["alice@example.com"]),
            ]
        )

        let rule = Rule(
            clauses: [
                RuleCondition(attribute: "email", comparison: "contains", value: .string("example.com")),
            ],
            value: .string("matched")
        )

        XCTAssertEqual(engine.evaluate([rule], context: context)?.value, .string("matched"))
    }

    func testEvaluatesNotContainsClause() {
        let engine = RuleEngine()
        let context = Context(
            type: "user",
            identifier: "user-123",
            attributes: [
                Attribute("email", values: ["alice@example.com"]),
            ]
        )

        let rule = Rule(
            clauses: [
                RuleCondition(attribute: "email", comparison: "notcontains", value: .string("other.com")),
            ],
            value: .string("matched")
        )

        XCTAssertEqual(engine.evaluate([rule], context: context)?.value, .string("matched"))
    }

    func testEvaluatesNotStartsWithClause() {
        let engine = RuleEngine()
        let context = Context(
            type: "user",
            identifier: "user-123",
            attributes: [
                Attribute("email", values: ["alice@example.com"]),
            ]
        )

        let rule = Rule(
            clauses: [
                RuleCondition(attribute: "email", comparison: "notstartswith", value: .string("admin")),
            ],
            value: .string("matched")
        )

        XCTAssertEqual(engine.evaluate([rule], context: context)?.value, .string("matched"))
    }

    func testEvaluatesNotEndsWithClause() {
        let engine = RuleEngine()
        let context = Context(
            type: "user",
            identifier: "user-123",
            attributes: [
                Attribute("email", values: ["alice@example.com"]),
            ]
        )

        let rule = Rule(
            clauses: [
                RuleCondition(attribute: "email", comparison: "notendswith", value: .string(".org")),
            ],
            value: .string("matched")
        )

        XCTAssertEqual(engine.evaluate([rule], context: context)?.value, .string("matched"))
    }

    func testIsNullMatchesWhenAttributeIsAbsent() {
        let engine = RuleEngine()
        let context = Context(type: "user", identifier: "user-123")
        let rule = Rule(
            clauses: [RuleCondition(attribute: "tag", comparison: "isnull", value: nil)],
            value: .string("matched")
        )
        XCTAssertEqual(engine.evaluate([rule], context: context)?.value, .string("matched"))
    }

    func testIsNullMatchesWhenAttributeValueIsEmpty() {
        let engine = RuleEngine()
        let context = Context(
            type: "user",
            identifier: "user-123",
            attributes: [Attribute("tag", values: [""])]
        )
        let rule = Rule(
            clauses: [RuleCondition(attribute: "tag", comparison: "isnull", value: nil)],
            value: .string("matched")
        )
        XCTAssertEqual(engine.evaluate([rule], context: context)?.value, .string("matched"))
    }

    func testNotNullMatchesWhenAttributeHasValue() {
        let engine = RuleEngine()
        let context = Context(
            type: "user",
            identifier: "user-123",
            attributes: [Attribute("tag", values: ["active"])]
        )
        let rule = Rule(
            clauses: [RuleCondition(attribute: "tag", comparison: "notnull", value: nil)],
            value: .string("matched")
        )
        XCTAssertEqual(engine.evaluate([rule], context: context)?.value, .string("matched"))
    }

    func testNotNullDoesNotMatchWhenAttributeIsAbsent() {
        let engine = RuleEngine()
        let context = Context(type: "user", identifier: "user-123")
        let rule = Rule(
            clauses: [RuleCondition(attribute: "tag", comparison: "notnull", value: nil)],
            value: .string("matched")
        )
        XCTAssertNil(engine.evaluate([rule], context: context))
    }

    func testNegativeOperatorsMatchWhenAttributeIsAbsent() {
        let engine = RuleEngine()
        let context = Context(type: "user", identifier: "user-123")
        for op in ["notequal", "notin", "notcontains", "notstartswith", "notendswith"] {
            let rule = Rule(
                clauses: [RuleCondition(attribute: "missing", comparison: op, value: .string("x"))],
                value: .string("matched")
            )
            XCTAssertNotNil(engine.evaluate([rule], context: context), "\(op) should match absent attr")
        }
    }
}