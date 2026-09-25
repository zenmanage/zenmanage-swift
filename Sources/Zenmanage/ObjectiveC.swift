import Foundation

/// Objective-C compatible attribute wrapper.
@objc(ZMObjCAttribute)
public final class ObjCAttribute: NSObject {
    let attribute: Attribute

    @objc public let key: String
    @objc public let values: [String]

    @objc public init(key: String, values: [String] = []) {
        self.key = key
        self.values = values
        attribute = Attribute(key, values: values)
        super.init()
    }
}

/// Objective-C compatible context wrapper.
@objc(ZMObjCContext)
public final class ObjCContext: NSObject {
    let context: Context

    @objc public let type: String
    @objc public let name: String?
    @objc public let identifier: String?
    @objc public let attributes: [ObjCAttribute]

    @objc public init(type: String, name: String? = nil, identifier: String? = nil, attributes: [ObjCAttribute] = []) {
        self.type = type
        self.name = name
        self.identifier = identifier
        self.attributes = attributes
        context = Context(type: type, name: name, identifier: identifier, attributes: attributes.map(\.attribute))
        super.init()
    }

    @objc public static func single(type: String, identifier: String, name: String? = nil) -> ObjCContext {
        ObjCContext(type: type, name: name, identifier: identifier)
    }
}

/// Objective-C compatible defaults wrapper.
@objc(ZMObjCDefaultsCollection)
public final class ObjCDefaultsCollection: NSObject {
    let defaults = DefaultsCollection()

    @objc @discardableResult public func setBool(_ value: Bool, forKey key: String) -> ObjCDefaultsCollection {
        defaults.set(key, bool: value)
        return self
    }

    @objc @discardableResult public func setString(_ value: String, forKey key: String) -> ObjCDefaultsCollection {
        defaults.set(key, string: value)
        return self
    }

    @objc @discardableResult public func setNumber(_ value: NSNumber, forKey key: String) -> ObjCDefaultsCollection {
        defaults.set(key, number: value.doubleValue)
        return self
    }
}

/// Objective-C compatible flag wrapper.
@objc(ZMObjCFlag)
public final class ObjCFlag: NSObject {
    private let flag: Flag

    @objc public let key: String
    @objc public let name: String
    @objc public let type: String

    init(flag: Flag) {
        self.flag = flag
        key = flag.key
        name = flag.name
        type = flag.type.rawValue
        super.init()
    }

    @objc public func isEnabled() -> Bool {
        flag.isEnabled()
    }

    @objc public func asBool() -> Bool {
        flag.asBool()
    }

    @objc public func asString() -> String {
        flag.asString()
    }

    @objc public func asNumber() -> NSNumber {
        NSNumber(value: flag.asNumber())
    }

    @objc public func asJson() -> Any {
        flag.asJson().foundationValue
    }
}

extension JSONValue {
    /// Bridges to a Foundation object graph (`NSDictionary`/`NSArray`/`NSString`/`NSNumber`/
    /// `NSNull`) suitable for passing across the Objective-C boundary.
    var foundationValue: Any {
        switch self {
        case let .object(value):
            return value.mapValues { $0.foundationValue } as NSDictionary
        case let .array(value):
            return value.map { $0.foundationValue } as NSArray
        case let .string(value):
            return value as NSString
        case let .number(value):
            return NSNumber(value: value)
        case let .boolean(value):
            return NSNumber(value: value)
        case .null:
            return NSNull()
        }
    }
}

/// Objective-C compatible flag manager wrapper.
@objc(ZMObjCFlagManager)
public final class ObjCFlagManager: NSObject {
    private let manager: FlagManager

    init(manager: FlagManager) {
        self.manager = manager
        super.init()
    }

    @objc public func withContext(_ context: ObjCContext) -> ObjCFlagManager {
        ObjCFlagManager(manager: manager.withContext(context.context))
    }

    @objc public func withDefaults(_ defaults: ObjCDefaultsCollection) -> ObjCFlagManager {
        ObjCFlagManager(manager: manager.withDefaults(defaults.defaults))
    }

    @objc public func refreshRulesWithCompletion(_ completion: @escaping (NSError?) -> Void) {
        Task {
            do {
                try await manager.refreshRules()
                completion(nil)
            } catch {
                completion(error.zenmanageNSError)
            }
        }
    }

    @objc public func allWithContext(_ context: ObjCContext?, completion: @escaping ([ObjCFlag]?, NSError?) -> Void) {
        let scopedManager = context.map { manager.withContext($0.context) } ?? manager

        Task {
            do {
                let flags = try await scopedManager.all().map(ObjCFlag.init)
                completion(flags, nil)
            } catch {
                completion(nil, error.zenmanageNSError)
            }
        }
    }

    @objc public func single(
        _ key: String,
        defaultValue: NSObject? = nil,
        context: ObjCContext? = nil,
        completion: @escaping (ObjCFlag?, NSError?) -> Void
    ) {
        let scopedManager = context.map { manager.withContext($0.context) } ?? manager

        Task {
            do {
                let flag: Flag

                switch defaultValue {
                case let value as NSString:
                    flag = try await scopedManager.single(key, defaultValue: value as String)
                case let value as NSNumber:
                    if CFGetTypeID(value) == CFBooleanGetTypeID() {
                        flag = try await scopedManager.single(key, defaultValue: value.boolValue)
                    } else {
                        flag = try await scopedManager.single(key, defaultValue: value.doubleValue)
                    }
                case nil:
                    flag = try await scopedManager.single(key)
                default:
                    throw ZenmanageError.configuration("Objective-C defaults must be NSString or NSNumber")
                }

                completion(ObjCFlag(flag: flag), nil)
            } catch {
                completion(nil, error.zenmanageNSError)
            }
        }
    }
}

/// Objective-C compatible main SDK wrapper.
@objc(ZMObjCZenmanage)
public final class ObjCZenmanage: NSObject {
    private let sdk: Zenmanage

    @objc public init(
        environmentToken: String,
        cacheTTL: NSNumber = 3600,
        enableUsageReporting: Bool = true,
        apiEndpoint: String = "https://api.zenmanage.com"
    ) throws {
        guard let endpointURL = URL(string: apiEndpoint) else {
            throw ZenmanageError.configuration("Invalid API endpoint URL")
        }

        sdk = try Zenmanage(
            environmentToken: environmentToken,
            cacheTTL: cacheTTL.doubleValue,
            cache: UserDefaultsRuleCache(),
            enableUsageReporting: enableUsageReporting,
            apiEndpoint: endpointURL
        )

        super.init()
    }

    @objc public func flags() -> ObjCFlagManager {
        ObjCFlagManager(manager: sdk.flags())
    }
}