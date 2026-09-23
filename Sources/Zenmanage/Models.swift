import Foundation

/// The supported Zenmanage flag types.
///
/// `unknown` covers any flag type the running SDK doesn't recognize yet (for example a
/// `json` flag served to an SDK release that predates json flag support). It decodes
/// without throwing so one unrecognized flag never drops the whole rules payload; flag
/// lookup treats a flag with this type the same as a flag that wasn't found at all.
public enum FlagType: String, Codable, Hashable, Sendable {
    case boolean
    case string
    case number
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if let knownType = FlagType(rawValue: rawValue) {
            self = knownType
        } else {
            self = .unknown
            Self.logUnrecognized(rawValue, decoder: decoder)
        }
    }

    private static func logUnrecognized(_ rawValue: String, decoder: Decoder) {
        (decoder.userInfo[.zenmanageLogger] as? any ZenmanageLogger)?.warn(
            "Unrecognized flag type; treating flag as unknown so the rest of the payload keeps evaluating",
            metadata: ["type": rawValue]
        )
    }
}

/// A typed flag value returned by Zenmanage.
///
/// `unknown` is the sentinel used when the value payload doesn't match any recognized
/// shape (for example a json flag's `{"json": ...}` wrapper, served to an SDK release
/// that predates json flag support). It decodes without throwing; evaluation treats a
/// flag whose value is `unknown` the same as a missing flag and falls back to the
/// caller-supplied default.
public enum FlagValue: Hashable, Sendable, Codable {
    case boolean(Bool)
    case string(String)
    case number(Double)
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let boolValue = try? container.decode(Bool.self) {
            self = .boolean(boolValue)
            return
        }

        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }

        if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
            return
        }

        self = .unknown
        (decoder.userInfo[.zenmanageLogger] as? any ZenmanageLogger)?.warn(
            "Unrecognized flag value; treating value as unknown so the rest of the payload keeps evaluating",
            metadata: nil
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .boolean(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case .unknown:
            try container.encodeNil()
        }
    }

    public var boolValue: Bool {
        switch self {
        case let .boolean(value):
            return value
        case let .string(value):
            return !value.isEmpty && value.lowercased() != "false" && value != "0"
        case let .number(value):
            return value != 0
        case .unknown:
            return false
        }
    }

    public var stringValue: String {
        switch self {
        case let .boolean(value):
            return String(value)
        case let .string(value):
            return value
        case let .number(value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .unknown:
            return ""
        }
    }

    public var numberValue: Double {
        switch self {
        case let .boolean(value):
            return value ? 1 : 0
        case let .string(value):
            return Double(value) ?? 0
        case let .number(value):
            return value
        case .unknown:
            return 0
        }
    }
}

extension FlagValue: CustomStringConvertible {
    public var description: String {
        stringValue
    }
}

/// A context selector used by `context` or `segment` rules.
public struct ContextTarget: Codable, Hashable, Sendable {
    public let identifier: String
    public let type: String?

    public init(identifier: String, type: String? = nil) {
        self.identifier = identifier
        self.type = type
    }
}

/// A rule condition value, which can be either string-based or context-target-based.
public enum RuleConditionValue: Hashable, Sendable, Codable {
    case string(String)
    case strings([String])
    case contextTarget(ContextTarget)
    case contextTargets([ContextTarget])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }

        if let stringValues = try? container.decode([String].self) {
            self = .strings(stringValues)
            return
        }

        if let target = try? container.decode(ContextTarget.self) {
            self = .contextTarget(target)
            return
        }

        if let targets = try? container.decode([ContextTarget].self) {
            self = .contextTargets(targets)
            return
        }

        throw DecodingError.typeMismatch(
            RuleConditionValue.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported rule condition value")
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .strings(values):
            try container.encode(values)
        case let .contextTarget(target):
            try container.encode(target)
        case let .contextTargets(targets):
            try container.encode(targets)
        }
    }

    var stringValues: [String]? {
        switch self {
        case let .string(value):
            return [value]
        case let .strings(values):
            return values
        case .contextTarget, .contextTargets:
            return nil
        }
    }

    var targets: [ContextTarget] {
        switch self {
        case let .string(value):
            return [ContextTarget(identifier: value)]
        case let .strings(values):
            return values.map { ContextTarget(identifier: $0) }
        case let .contextTarget(target):
            return [target]
        case let .contextTargets(targets):
            return targets
        }
    }
}

/// A single rule condition.
public struct RuleCondition: Codable, Hashable, Sendable {
    public let attribute: String
    public let comparison: String
    public let value: RuleConditionValue?

    public init(attribute: String, comparison: String, value: RuleConditionValue? = nil) {
        self.attribute = attribute
        self.comparison = comparison
        self.value = value
    }

    // CodingKeys covers both legacy format (attribute/operator/value) and CDN format
    // (selector/selector_subtype/comparer/values). The custom decoder below handles both.
    private enum CodingKeys: String, CodingKey {
        case attribute
        case comparison = "operator"
        case value
        case selector
        case selectorSubtype = "selector_subtype"
        case comparer
        case values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let selector = try container.decodeIfPresent(String.self, forKey: .selector) {
            // CDN format: selector / selector_subtype / comparer / values
            let selectorSubtype = try container.decodeIfPresent(String.self, forKey: .selectorSubtype)
            attribute = (selector == "attribute") ? (selectorSubtype ?? selector) : selector
            comparison = try container.decode(String.self, forKey: .comparer)
            value = try container.decodeIfPresent(RuleConditionValue.self, forKey: .values)
        } else {
            // Legacy format: attribute / operator / value
            attribute = try container.decode(String.self, forKey: .attribute)
            comparison = try container.decode(String.self, forKey: .comparison)
            value = try container.decodeIfPresent(RuleConditionValue.self, forKey: .value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(attribute, forKey: .attribute)
        try container.encode(comparison, forKey: .comparison)
        try container.encodeIfPresent(value, forKey: .value)
    }
}

/// A rule target that overrides the base flag value when matched.
public struct Rule: Codable, Hashable, Sendable {
    public let version: String?
    public let description: String?
    public let criteria: RuleCondition?
    public let clauses: [RuleCondition]
    public let position: Int?
    public let value: FlagValue

    public init(
        version: String? = nil,
        description: String? = nil,
        criteria: RuleCondition? = nil,
        clauses: [RuleCondition] = [],
        position: Int? = nil,
        value: FlagValue
    ) {
        self.version = version
        self.description = description
        self.criteria = criteria
        self.clauses = clauses
        self.position = position
        self.value = value
    }

    enum CodingKeys: String, CodingKey {
        case version
        case description
        case criteria
        case clauses
        case position
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        criteria = try container.decodeIfPresent(RuleCondition.self, forKey: .criteria)
        clauses = try container.decodeIfPresent([RuleCondition].self, forKey: .clauses) ?? []
        position = try container.decodeIfPresent(Int.self, forKey: .position)

        if let wrapper = try? container.decode(APIRuleValue.self, forKey: .value) {
            value = wrapper.value.flagValue
        } else {
            value = try container.decode(FlagValue.self, forKey: .value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(criteria, forKey: .criteria)
        if !clauses.isEmpty {
            try container.encode(clauses, forKey: .clauses)
        }
        try container.encodeIfPresent(position, forKey: .position)
        try container.encode(value, forKey: .value)
    }
}

/// The effective target value for a flag.
public struct FlagTarget: Codable, Hashable, Sendable {
    public let version: String?
    public let expiredAt: String?
    public let publishedAt: String?
    public let scheduledAt: String?
    public let value: FlagValue

    public init(
        version: String? = nil,
        expiredAt: String? = nil,
        publishedAt: String? = nil,
        scheduledAt: String? = nil,
        value: FlagValue
    ) {
        self.version = version
        self.expiredAt = expiredAt
        self.publishedAt = publishedAt
        self.scheduledAt = scheduledAt
        self.value = value
    }

    enum CodingKeys: String, CodingKey {
        case version
        case expiredAt = "expired_at"
        case publishedAt = "published_at"
        case scheduledAt = "scheduled_at"
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        expiredAt = try container.decodeIfPresent(String.self, forKey: .expiredAt)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        scheduledAt = try container.decodeIfPresent(String.self, forKey: .scheduledAt)

        if let wrapper = try? container.decode(APIRuleValue.self, forKey: .value) {
            value = wrapper.value.flagValue
        } else {
            value = try container.decode(FlagValue.self, forKey: .value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(expiredAt, forKey: .expiredAt)
        try container.encodeIfPresent(publishedAt, forKey: .publishedAt)
        try container.encodeIfPresent(scheduledAt, forKey: .scheduledAt)
        try container.encode(value, forKey: .value)
    }
}

/// Percentage rollout data returned by the API.
public struct Rollout: Codable, Hashable, Sendable {
    public let target: FlagTarget
    public let rules: [Rule]
    public let percentage: Double
    public let salt: String
    public let status: String

    public init(target: FlagTarget, rules: [Rule], percentage: Double, salt: String, status: String) {
        self.target = target
        self.rules = rules
        self.percentage = percentage
        self.salt = salt
        self.status = status
    }
}

/// A single feature flag with its metadata and evaluation helpers.
public struct Flag: Codable, Hashable, Sendable {
    public let version: String
    public let type: FlagType
    public let key: String
    public let name: String
    public let target: FlagTarget
    public let rules: [Rule]
    public let rollout: Rollout?

    public init(
        version: String,
        type: FlagType,
        key: String,
        name: String,
        target: FlagTarget,
        rules: [Rule] = [],
        rollout: Rollout? = nil
    ) {
        self.version = version
        self.type = type
        self.key = key
        self.name = name
        self.target = target
        self.rules = rules
        self.rollout = rollout
    }

    enum CodingKeys: String, CodingKey {
        case version
        case type
        case key
        case name
        case target
        case rules
        case rollout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        type = try container.decode(FlagType.self, forKey: .type)
        key = try container.decode(String.self, forKey: .key)
        name = try container.decode(String.self, forKey: .name)
        target = try container.decode(FlagTarget.self, forKey: .target)
        rules = try container.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        rollout = try container.decodeIfPresent(Rollout.self, forKey: .rollout)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(type, forKey: .type)
        try container.encode(key, forKey: .key)
        try container.encode(name, forKey: .name)
        try container.encode(target, forKey: .target)
        if !rules.isEmpty {
            try container.encode(rules, forKey: .rules)
        }
        try container.encodeIfPresent(rollout, forKey: .rollout)
    }

    public var value: FlagValue {
        target.value
    }

    /// True when this flag's type wasn't recognized by this SDK release (for example a
    /// json flag served to an SDK that predates json flag support). Flag lookup treats
    /// such a flag the same as one that wasn't found, falling back to the caller's default.
    var isUnknownType: Bool {
        type == .unknown
    }

    public func isEnabled() -> Bool {
        guard type == .boolean else {
            return false
        }

        return value.boolValue
    }

    public func asBool() -> Bool {
        value.boolValue
    }

    public func asString() -> String {
        value.stringValue
    }

    public func asNumber() -> Double {
        value.numberValue
    }

    func with(target: FlagTarget, rules: [Rule]) -> Flag {
        Flag(version: version, type: type, key: key, name: name, target: target, rules: rules)
    }
}

/// A multi-value context attribute used for client-side rule evaluation.
public struct Attribute: Codable, Hashable, Sendable {
    public let key: String
    public private(set) var values: [String]

    public init(_ key: String, values: [String] = []) {
        self.key = key
        self.values = values
    }

    public mutating func addValue(_ value: String) {
        values.append(value)
    }

    enum CodingKeys: String, CodingKey {
        case key
        case values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)

        let nestedValues = try container.decode([AttributeValuePayload].self, forKey: .values)
        values = nestedValues.map(\.value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(values.map(AttributeValuePayload.init), forKey: .values)
    }
}

/// The evaluation context for rules and usage reporting.
public struct Context: Codable, Hashable, Sendable {
    public let type: String
    public let name: String?
    public let identifier: String?
    public private(set) var attributes: [Attribute]

    public init(type: String, name: String? = nil, identifier: String? = nil, attributes: [Attribute] = []) {
        self.type = type
        self.name = name
        self.identifier = identifier
        self.attributes = attributes
    }

    public static func single(type: String, identifier: String, name: String? = nil) -> Context {
        Context(type: type, name: name, identifier: identifier)
    }

    public func attribute(forKey key: String) -> Attribute? {
        attributes.first(where: { $0.key == key })
    }

    public func hasAttribute(_ key: String) -> Bool {
        attribute(forKey: key) != nil
    }

    public func addingAttribute(_ attribute: Attribute) -> Context {
        var copy = self
        copy.attributes.removeAll(where: { $0.key == attribute.key })
        copy.attributes.append(attribute)
        return copy
    }

    var isAnonymousWithoutData: Bool {
        type == "anonymous" && name == nil && identifier == nil && attributes.isEmpty
    }
}

/// Mutable defaults used when a flag is missing from the fetched rules.
public final class DefaultsCollection {
    private var storage: [String: FlagValue]

    public init(_ storage: [String: FlagValue] = [:]) {
        self.storage = storage
    }

    public static func fromDictionary(_ values: [String: FlagValue]) -> DefaultsCollection {
        DefaultsCollection(values)
    }

    @discardableResult
    public func set(_ key: String, value: FlagValue) -> DefaultsCollection {
        storage[key] = value
        return self
    }

    @discardableResult
    public func set(_ key: String, bool value: Bool) -> DefaultsCollection {
        set(key, value: .boolean(value))
    }

    @discardableResult
    public func set(_ key: String, string value: String) -> DefaultsCollection {
        set(key, value: .string(value))
    }

    @discardableResult
    public func set(_ key: String, number value: Double) -> DefaultsCollection {
        set(key, value: .number(value))
    }

    @discardableResult
    public func set(_ key: String, int value: Int) -> DefaultsCollection {
        set(key, value: .number(Double(value)))
    }

    public func get(_ key: String) -> FlagValue? {
        storage[key]
    }

    public func has(_ key: String) -> Bool {
        storage[key] != nil
    }

    public func delete(_ key: String) {
        storage.removeValue(forKey: key)
    }

    public func clear() {
        storage.removeAll()
    }

    public func size() -> Int {
        storage.count
    }

    public func keys() -> [String] {
        storage.keys.sorted()
    }
}

struct RulesEnvelope: Codable {
    let version: String
    let flags: [Flag]
}

private struct AttributeValuePayload: Codable {
    let value: String

    init(_ value: String) {
        self.value = value
    }
}

private struct APIRuleValue: Codable {
    let version: String?
    let value: APITypedValue
}

private struct APITypedValue: Codable {
    let boolean: Bool?
    let string: String?
    let number: Double?

    private enum CodingKeys: String, CodingKey {
        case boolean
        case string
        case number
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        boolean = try container.decodeIfPresent(Bool.self, forKey: .boolean)
        string = try container.decodeIfPresent(String.self, forKey: .string)
        number = try container.decodeIfPresent(Double.self, forKey: .number)

        // If none of the recognized keys were present (e.g. a json flag's
        // `{"json": ...}` wrapper), `flagValue` below falls back to `.unknown`. Unknown
        // keys are otherwise ignored by keyed decoding, so this is the only signal we
        // get that the wrapper didn't match a known flag value shape. This isn't logged
        // here to avoid double-logging: an unrecognized value wrapper always accompanies
        // an unrecognized `FlagType`, whose own `init(from:)` already logs it once.
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(boolean, forKey: .boolean)
        try container.encodeIfPresent(string, forKey: .string)
        try container.encodeIfPresent(number, forKey: .number)
    }

    var flagValue: FlagValue {
        if let boolean {
            return .boolean(boolean)
        }

        if let string {
            return .string(string)
        }

        if let number {
            return .number(number)
        }

        return .unknown
    }
}