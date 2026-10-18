import XCTest
@testable import Zenmanage

final class JSONValueTests: XCTestCase {
    private func decode(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode([JSONValue].self, from: Data("[\(json)]".utf8))[0]
    }

    func testDecodesEveryJSONShape() throws {
        XCTAssertEqual(try decode("null"), .null)
        XCTAssertEqual(try decode("true"), .boolean(true))
        XCTAssertEqual(try decode("2.5"), .number(2.5))
        XCTAssertEqual(try decode("\"hi\""), .string("hi"))
        XCTAssertEqual(try decode("[1,\"a\"]"), .array([.number(1), .string("a")]))
        XCTAssertEqual(try decode("{\"k\":[null]}"), .object(["k": .array([.null])]))
    }

    func testRoundTripsThroughCodable() throws {
        let value: JSONValue = ["a": [1, true, nil, "x", 2.5], "b": ["c": "d"]]

        let data = try JSONEncoder().encode([value])
        let decoded = try JSONDecoder().decode([JSONValue].self, from: data)

        XCTAssertEqual(decoded, [value])
    }

    func testLiteralConformances() {
        let null: JSONValue = nil
        let bool: JSONValue = true
        let int: JSONValue = 3
        let float: JSONValue = 1.5
        let string: JSONValue = "s"

        XCTAssertEqual(null, .null)
        XCTAssertEqual(bool, .boolean(true))
        XCTAssertEqual(int, .number(3))
        XCTAssertEqual(float, .number(1.5))
        XCTAssertEqual(string, .string("s"))
    }

    func testOnlyObjectsAndArraysAreContainers() {
        XCTAssertTrue(JSONValue.object([:]).isContainer)
        XCTAssertTrue(JSONValue.array([]).isContainer)
        XCTAssertFalse(JSONValue.string("x").isContainer)
        XCTAssertFalse(JSONValue.number(1).isContainer)
        XCTAssertFalse(JSONValue.boolean(true).isContainer)
        XCTAssertFalse(JSONValue.null.isContainer)
    }
}

final class FlagValueTests: XCTestCase {
    func testBoolValueCoercion() {
        XCTAssertTrue(FlagValue.boolean(true).boolValue)
        XCTAssertFalse(FlagValue.boolean(false).boolValue)
        XCTAssertTrue(FlagValue.string("yes").boolValue)
        XCTAssertFalse(FlagValue.string("").boolValue)
        XCTAssertFalse(FlagValue.string("FALSE").boolValue)
        XCTAssertFalse(FlagValue.string("0").boolValue)
        XCTAssertTrue(FlagValue.number(2).boolValue)
        XCTAssertFalse(FlagValue.number(0).boolValue)
        XCTAssertTrue(FlagValue.json(["a": 1]).boolValue)
        XCTAssertFalse(FlagValue.unknown.boolValue)
    }

    func testStringValueCoercion() {
        XCTAssertEqual(FlagValue.boolean(true).stringValue, "true")
        XCTAssertEqual(FlagValue.string("x").stringValue, "x")
        XCTAssertEqual(FlagValue.number(1500).stringValue, "1500")
        XCTAssertEqual(FlagValue.number(-3).stringValue, "-3")
        XCTAssertEqual(FlagValue.number(2.5).stringValue, "2.5")
        XCTAssertEqual(FlagValue.json(["a": 1]).stringValue, "")
        XCTAssertEqual(FlagValue.unknown.stringValue, "")
        XCTAssertEqual(FlagValue.number(1500).description, "1500")
    }

    func testStringValueDoesNotTrapOnNumbersOutsideIntRange() {
        // `Int(value)` would trap for each of these.
        XCTAssertFalse(FlagValue.number(1e300).stringValue.isEmpty)
        XCTAssertFalse(FlagValue.number(9.3e18).stringValue.isEmpty)
        XCTAssertFalse(FlagValue.number(-1e30).stringValue.isEmpty)
        XCTAssertFalse(FlagValue.number(.infinity).stringValue.isEmpty)
        XCTAssertFalse(FlagValue.number(.nan).stringValue.isEmpty)
    }

    func testNumberValueCoercion() {
        XCTAssertEqual(FlagValue.boolean(true).numberValue, 1)
        XCTAssertEqual(FlagValue.boolean(false).numberValue, 0)
        XCTAssertEqual(FlagValue.string("3.5").numberValue, 3.5)
        XCTAssertEqual(FlagValue.string("abc").numberValue, 0)
        XCTAssertEqual(FlagValue.number(7).numberValue, 7)
        XCTAssertEqual(FlagValue.json([1, 2]).numberValue, 0)
        XCTAssertEqual(FlagValue.unknown.numberValue, 0)
    }

    func testJsonValueOnlyRecognizesContainers() {
        XCTAssertEqual(FlagValue.json(["a": 1]).jsonValue, ["a": 1])
        XCTAssertEqual(FlagValue.json([1, 2, 3]).jsonValue, [1, 2, 3])
        XCTAssertEqual(FlagValue.json(.number(5)).jsonValue, .empty)
        XCTAssertEqual(FlagValue.boolean(true).jsonValue, .empty)
        XCTAssertEqual(FlagValue.string("x").jsonValue, .empty)
        XCTAssertEqual(FlagValue.number(1).jsonValue, .empty)
        XCTAssertEqual(FlagValue.unknown.jsonValue, .empty)
    }

    func testDecodesEachWireShape() throws {
        let values = try JSONDecoder().decode(
            [FlagValue].self,
            from: Data("[true,\"s\",4.5,{\"a\":1},[1,2]]".utf8)
        )

        XCTAssertEqual(values, [.boolean(true), .string("s"), .number(4.5), .json(["a": 1]), .json([1, 2])])
    }

    func testDecodingAnUnrecognizedValueYieldsUnknownAndLogsOnce() throws {
        let logger = RecordingLogger()
        let decoder = JSONDecoder()
        decoder.userInfo[.zenmanageLogger] = logger

        let values = try decoder.decode([FlagValue].self, from: Data("[null]".utf8))

        XCTAssertEqual(values, [.unknown])
        XCTAssertEqual(logger.warnings.count, 1)
    }

    func testEncodesBackToTheSameWireShape() throws {
        let values: [FlagValue] = [.boolean(false), .string("s"), .number(2), .json(["a": [1]]), .unknown]

        let data = try JSONEncoder().encode(values)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(text.hasPrefix("[false,\"s\",2"), text)
        XCTAssertTrue(text.hasSuffix("null]"), text)
    }
}

final class RuleModelTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testRuleConditionValueDecodesEveryShape() throws {
        XCTAssertEqual(try decode([RuleConditionValue].self, "[\"a\"]"), [.string("a")])
        XCTAssertEqual(try decode([RuleConditionValue].self, "[[\"a\",\"b\"]]"), [.strings(["a", "b"])])
        XCTAssertEqual(
            try decode([RuleConditionValue].self, "[{\"identifier\":\"u1\",\"type\":\"user\"}]"),
            [.contextTarget(ContextTarget(identifier: "u1", type: "user"))]
        )
        XCTAssertEqual(
            try decode([RuleConditionValue].self, "[[{\"identifier\":\"u1\",\"type\":null},{\"identifier\":\"u2\"}]]"),
            [.contextTargets([ContextTarget(identifier: "u1"), ContextTarget(identifier: "u2")])]
        )
    }

    func testRuleConditionValueRejectsUnsupportedShapes() {
        XCTAssertThrowsError(try decode([RuleConditionValue].self, "[5]"))
        XCTAssertThrowsError(try decode([RuleConditionValue].self, "[true]"))
    }

    func testRuleConditionValueRoundTrips() throws {
        let values: [RuleConditionValue] = [
            .string("a"),
            .strings(["a", "b"]),
            .contextTarget(ContextTarget(identifier: "u1", type: "user")),
            .contextTargets([ContextTarget(identifier: "u1"), ContextTarget(identifier: "u2", type: "org")]),
        ]

        let decoded = try JSONDecoder().decode([RuleConditionValue].self, from: JSONEncoder().encode(values))

        XCTAssertEqual(decoded, values)
    }

    func testRuleConditionValueAccessors() {
        XCTAssertEqual(RuleConditionValue.string("a").stringValues, ["a"])
        XCTAssertEqual(RuleConditionValue.strings(["a", "b"]).stringValues, ["a", "b"])
        XCTAssertNil(RuleConditionValue.contextTarget(ContextTarget(identifier: "u")).stringValues)
        XCTAssertNil(RuleConditionValue.contextTargets([]).stringValues)

        XCTAssertEqual(RuleConditionValue.string("a").targets, [ContextTarget(identifier: "a")])
        XCTAssertEqual(RuleConditionValue.strings(["a", "b"]).targets.map(\.identifier), ["a", "b"])
        XCTAssertEqual(RuleConditionValue.contextTarget(ContextTarget(identifier: "u", type: "user")).targets.count, 1)
    }

    func testRuleConditionDecodesTheLegacyShape() throws {
        let condition = try decode(
            RuleCondition.self,
            "{\"attribute\":\"country\",\"operator\":\"equal\",\"value\":\"US\"}"
        )

        XCTAssertEqual(condition, RuleCondition(attribute: "country", comparison: "equal", value: .string("US")))
    }

    func testRuleConditionDecodesTheCDNShape() throws {
        let attribute = try decode(
            RuleCondition.self,
            "{\"selector\":\"attribute\",\"selector_subtype\":\"plan\",\"comparer\":\"in\",\"values\":[\"pro\",\"team\"]}"
        )
        let context = try decode(
            RuleCondition.self,
            "{\"selector\":\"context\",\"selector_subtype\":null,\"comparer\":\"equal\",\"values\":[{\"identifier\":\"u1\",\"type\":null}]}"
        )
        let bareAttribute = try decode(
            RuleCondition.self,
            "{\"selector\":\"attribute\",\"comparer\":\"isnull\",\"values\":[]}"
        )

        XCTAssertEqual(attribute, RuleCondition(attribute: "plan", comparison: "in", value: .strings(["pro", "team"])))
        XCTAssertEqual(
            context,
            RuleCondition(attribute: "context", comparison: "equal", value: .contextTargets([ContextTarget(identifier: "u1")]))
        )
        XCTAssertEqual(bareAttribute.attribute, "attribute")
    }

    func testRuleConditionEncodesTheLegacyShapeAndDecodesItBack() throws {
        let condition = RuleCondition(attribute: "plan", comparison: "in", value: .strings(["pro"]))

        let decoded = try JSONDecoder().decode(RuleCondition.self, from: JSONEncoder().encode(condition))

        XCTAssertEqual(decoded, condition)
    }

    func testRuleDecodesWrappedAndBareValues() throws {
        let wrapped = try decode(
            Rule.self,
            "{\"version\":\"rul_1\",\"description\":\"d\",\"position\":3,\"value\":{\"version\":\"val_1\",\"value\":{\"boolean\":true}}}"
        )
        let bare = try decode(Rule.self, "{\"clauses\":[],\"value\":\"direct\"}")

        XCTAssertEqual(wrapped.version, "rul_1")
        XCTAssertEqual(wrapped.description, "d")
        XCTAssertEqual(wrapped.position, 3)
        XCTAssertEqual(wrapped.value, .boolean(true))
        XCTAssertNil(wrapped.criteria)
        XCTAssertEqual(bare.value, .string("direct"))
        XCTAssertNil(bare.position)
    }

    func testRuleRoundTrips() throws {
        let rule = Rule(
            version: "rul_1",
            description: "d",
            criteria: RuleCondition(attribute: "plan", comparison: "equal", value: .string("pro")),
            clauses: [RuleCondition(attribute: "country", comparison: "equal", value: .string("US"))],
            position: 2,
            value: .json(["a": 1])
        )

        let decoded = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(rule))

        XCTAssertEqual(decoded, rule)
    }

    func testRolloutAndFlagTargetInitializers() {
        let target = FlagTarget(version: "t1", expiredAt: "e", publishedAt: "p", scheduledAt: "s", value: .number(1))
        let rollout = Rollout(target: target, rules: [], percentage: 25, salt: "salt", status: "active")

        XCTAssertEqual(rollout.target, target)
        XCTAssertEqual(rollout.percentage, 25)
        XCTAssertEqual(rollout.salt, "salt")
        XCTAssertEqual(rollout.status, "active")
        XCTAssertEqual(target.expiredAt, "e")
    }

    func testFlagWithRolloutRoundTripsThroughCodable() throws {
        let target = FlagTarget(version: "t1", value: .string("control"))
        let rollout = Rollout(
            target: FlagTarget(version: "t2", value: .string("treatment")),
            rules: [],
            percentage: 50,
            salt: "salt",
            status: "active"
        )
        let flag = Flag(version: "f1", type: .string, key: "k", name: "K", target: target, rollout: rollout)

        let decoded = try JSONDecoder().decode(Flag.self, from: JSONEncoder().encode(flag))

        XCTAssertEqual(decoded, flag)
    }
}

final class ContextModelTests: XCTestCase {
    func testAttributeAddValueAppends() {
        var attribute = Attribute("tags", values: ["a"])

        attribute.addValue("b")

        XCTAssertEqual(attribute.values, ["a", "b"])
    }

    func testAttributeEncodesValuesAsObjectsAndDecodesThemBack() throws {
        let attribute = Attribute("tags", values: ["a", "b"])

        let data = try JSONEncoder().encode(attribute)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let values = try XCTUnwrap(object["values"] as? [[String: String]])

        XCTAssertEqual(object["key"] as? String, "tags")
        XCTAssertEqual(values, [["value": "a"], ["value": "b"]])
        XCTAssertEqual(try JSONDecoder().decode(Attribute.self, from: data), attribute)
    }

    func testSingleContextHasNoAttributes() {
        let context = Context.single(type: "user", identifier: "u1", name: "Una")

        XCTAssertEqual(context.type, "user")
        XCTAssertEqual(context.identifier, "u1")
        XCTAssertEqual(context.name, "Una")
        XCTAssertTrue(context.attributes.isEmpty)
        XCTAssertEqual(Context.single(type: "user", identifier: "u1").name, nil)
    }

    func testAttributeLookup() {
        let context = Context(type: "user", attributes: [Attribute("country", values: ["US"])])

        XCTAssertTrue(context.hasAttribute("country"))
        XCTAssertFalse(context.hasAttribute("plan"))
        XCTAssertEqual(context.attribute(forKey: "country")?.values, ["US"])
        XCTAssertNil(context.attribute(forKey: "plan"))
    }

    func testAddingAnAttributeReplacesOneWithTheSameKeyAndLeavesTheOriginalAlone() {
        let original = Context(type: "user", attributes: [Attribute("plan", values: ["free"]), Attribute("country", values: ["US"])])

        let updated = original.addingAttribute(Attribute("plan", values: ["pro"]))

        XCTAssertEqual(updated.attribute(forKey: "plan")?.values, ["pro"])
        XCTAssertEqual(updated.attributes.count, 2)
        XCTAssertEqual(original.attribute(forKey: "plan")?.values, ["free"])
    }

    func testOnlyABareAnonymousContextCountsAsAnonymousWithoutData() {
        XCTAssertTrue(Context(type: "anonymous").isAnonymousWithoutData)
        XCTAssertFalse(Context(type: "anonymous", identifier: "x").isAnonymousWithoutData)
        XCTAssertFalse(Context(type: "anonymous", name: "x").isAnonymousWithoutData)
        XCTAssertFalse(Context(type: "anonymous", attributes: [Attribute("a")]).isAnonymousWithoutData)
        XCTAssertFalse(Context(type: "user").isAnonymousWithoutData)
    }
}

final class DefaultsCollectionTests: XCTestCase {
    func testSettersStoreTypedValues() {
        let defaults = DefaultsCollection()
            .set("bool", bool: true)
            .set("string", string: "s")
            .set("number", number: 1.5)
            .set("int", int: 7)
            .set("json", json: ["a": 1])
            .set("raw", value: .string("r"))

        XCTAssertEqual(defaults.get("bool"), .boolean(true))
        XCTAssertEqual(defaults.get("string"), .string("s"))
        XCTAssertEqual(defaults.get("number"), .number(1.5))
        XCTAssertEqual(defaults.get("int"), .number(7))
        XCTAssertEqual(defaults.get("json"), .json(["a": 1]))
        XCTAssertEqual(defaults.get("raw"), .string("r"))
        XCTAssertNil(defaults.get("missing"))
    }

    func testSizeKeysHasDeleteAndClear() {
        let defaults = DefaultsCollection.fromDictionary(["a": .boolean(true), "b": .string("x")])

        XCTAssertEqual(defaults.size(), 2)
        XCTAssertEqual(Set(defaults.keys()), ["a", "b"])
        XCTAssertTrue(defaults.has("a"))
        XCTAssertFalse(defaults.has("c"))

        defaults.delete("a")
        XCTAssertFalse(defaults.has("a"))
        XCTAssertEqual(defaults.size(), 1)

        defaults.clear()
        XCTAssertEqual(defaults.size(), 0)
        XCTAssertTrue(defaults.keys().isEmpty)
    }

    func testSettingAKeyAgainReplacesItsValue() {
        let defaults = DefaultsCollection().set("k", bool: false)

        _ = defaults.set("k", bool: true)

        XCTAssertEqual(defaults.get("k"), .boolean(true))
        XCTAssertEqual(defaults.size(), 1)
    }
}
