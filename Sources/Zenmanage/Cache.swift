import Foundation

/// Cache interface used for storing serialized rules locally.
public protocol RuleCache {
    func get(_ key: String) throws -> String?
    func set(_ key: String, value: String, ttl: TimeInterval) throws
    func delete(_ key: String) throws
    func clear() throws
}

private struct CachedValue: Codable {
    let value: String
    let expiresAt: Date
}

/// UserDefaults-backed cache for iOS apps.
public final class UserDefaultsRuleCache: RuleCache {
    private let userDefaults: UserDefaults
    private let namespace: String
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(userDefaults: UserDefaults = .standard, namespace: String = "com.zenmanage.cache") {
        self.userDefaults = userDefaults
        self.namespace = namespace
    }

    public func get(_ key: String) throws -> String? {
        let namespacedKey = makeKey(key)

        guard let data = userDefaults.data(forKey: namespacedKey) else {
            return nil
        }

        do {
            let cachedValue = try decoder.decode(CachedValue.self, from: data)

            if cachedValue.expiresAt < Date() {
                userDefaults.removeObject(forKey: namespacedKey)
                return nil
            }

            return cachedValue.value
        } catch {
            userDefaults.removeObject(forKey: namespacedKey)
            throw ZenmanageError.cache("Failed to decode cached rules: \(error.localizedDescription)")
        }
    }

    public func set(_ key: String, value: String, ttl: TimeInterval) throws {
        let cachedValue = CachedValue(value: value, expiresAt: Date().addingTimeInterval(ttl))

        do {
            let data = try encoder.encode(cachedValue)
            userDefaults.set(data, forKey: makeKey(key))
        } catch {
            throw ZenmanageError.cache("Failed to encode cached rules: \(error.localizedDescription)")
        }
    }

    public func delete(_ key: String) throws {
        userDefaults.removeObject(forKey: makeKey(key))
    }

    public func clear() throws {
        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix("\(namespace).") {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func makeKey(_ key: String) -> String {
        "\(namespace).\(key)"
    }
}

/// Simple in-memory cache useful for tests and ephemeral sessions.
public final class InMemoryRuleCache: RuleCache {
    private let lock = NSLock()
    private var storage: [String: CachedValue] = [:]

    public init() {}

    public func get(_ key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let cachedValue = storage[key] else {
            return nil
        }

        if cachedValue.expiresAt < Date() {
            storage.removeValue(forKey: key)
            return nil
        }

        return cachedValue.value
    }

    public func set(_ key: String, value: String, ttl: TimeInterval) throws {
        lock.lock()
        storage[key] = CachedValue(value: value, expiresAt: Date().addingTimeInterval(ttl))
        lock.unlock()
    }

    public func delete(_ key: String) throws {
        lock.lock()
        storage.removeValue(forKey: key)
        lock.unlock()
    }

    public func clear() throws {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}

/// Cache implementation that disables persistence entirely.
public struct NullRuleCache: RuleCache {
    public init() {}

    public func get(_ key: String) throws -> String? {
        nil
    }

    public func set(_ key: String, value: String, ttl: TimeInterval) throws {}
    public func delete(_ key: String) throws {}
    public func clear() throws {}
}