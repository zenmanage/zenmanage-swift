import Foundation

final class FlagStore {
    private let lock = NSLock()
    private var flags: [Flag]?

    func currentFlags() -> [Flag]? {
        lock.lock()
        defer { lock.unlock() }
        return flags
    }

    func setFlags(_ flags: [Flag]) {
        lock.lock()
        self.flags = flags
        lock.unlock()
    }

    func clear() {
        lock.lock()
        flags = nil
        lock.unlock()
    }
}

/// Fetches, caches, and evaluates flags for the current context.
public final class FlagManager {
    private static let cacheKey = "zenmanage_rules"

    private let apiClient: APIClient
    private let cache: any RuleCache
    private let ruleEngine: RuleEngine
    private let cacheTTL: TimeInterval
    private let logger: any ZenmanageLogger
    private let store: FlagStore
    private let context: Context
    private let defaults: DefaultsCollection

    init(
        apiClient: APIClient,
        cache: any RuleCache,
        ruleEngine: RuleEngine,
        cacheTTL: TimeInterval,
        logger: any ZenmanageLogger,
        store: FlagStore = FlagStore(),
        context: Context = Context(type: "anonymous"),
        defaults: DefaultsCollection = DefaultsCollection()
    ) {
        self.apiClient = apiClient
        self.cache = cache
        self.ruleEngine = ruleEngine
        self.cacheTTL = cacheTTL
        self.logger = logger
        self.store = store
        self.context = context
        self.defaults = defaults
    }

    /// Returns all fetched flags evaluated against the current context.
    ///
    /// Flags whose type wasn't recognized by this SDK release (e.g. a json flag served
    /// to an SDK that predates json flag support) are omitted rather than returned with
    /// an unusable value.
    public func all() async throws -> [Flag] {
        let flags = try await ensureRulesLoaded()
        return try flags.filter { !$0.isUnknownType }.map(evaluateFlag)
    }

    /// Returns a single flag by key.
    ///
    /// A flag whose type wasn't recognized by this SDK release (e.g. a json flag served
    /// to an SDK that predates json flag support) is treated the same as a flag that
    /// wasn't found: it falls back to `defaultValue`, then the `DefaultsCollection`, then
    /// throws.
    public func single(_ key: String, defaultValue: FlagValue? = nil) async throws -> Flag {
        let flags = try await ensureRulesLoaded()

        if let flag = flags.first(where: { $0.key == key && !$0.isUnknownType }) {
            apiClient.reportUsage(key: key, context: usageContext(), defaultValue: resolveEffectiveDefault(key: key, defaultValue: defaultValue))
            return try evaluateFlag(flag)
        }

        if let defaultValue {
            apiClient.reportUsage(key: key, context: usageContext(), defaultValue: defaultValue)
            return createFlagFromDefault(key: key, value: defaultValue)
        }

        if let defaultValue = defaults.get(key) {
            apiClient.reportUsage(key: key, context: usageContext(), defaultValue: defaultValue)
            return createFlagFromDefault(key: key, value: defaultValue)
        }

        throw ZenmanageError.evaluation("Flag not found: \(key)")
    }

    /// Convenience overload for boolean defaults.
    public func single(_ key: String, defaultValue: Bool) async throws -> Flag {
        // `FlagValue` is spelled out (rather than `.boolean(...)`) because `FlagValue` and
        // `JSONValue` both have a `.boolean` case: with the `single(_:defaultValue:)`
        // overload set including a `JSONValue` parameter, the bare shorthand is ambiguous
        // and can silently resolve to the wrong enum.
        try await single(key, defaultValue: FlagValue.boolean(defaultValue))
    }

    /// Convenience overload for string defaults.
    public func single(_ key: String, defaultValue: String) async throws -> Flag {
        try await single(key, defaultValue: FlagValue.string(defaultValue))
    }

    /// Convenience overload for integer defaults.
    public func single(_ key: String, defaultValue: Int) async throws -> Flag {
        try await single(key, defaultValue: FlagValue.number(Double(defaultValue)))
    }

    /// Convenience overload for double defaults.
    public func single(_ key: String, defaultValue: Double) async throws -> Flag {
        try await single(key, defaultValue: FlagValue.number(defaultValue))
    }

    /// Convenience overload for json defaults (a `JSONValue.object` or `JSONValue.array`,
    /// which also accept Swift dictionary/array literals directly via `ExpressibleBy...`
    /// conformance). This synthesizes a `json`-typed flag rather than coercing the default
    /// to a string.
    public func single(_ key: String, defaultValue: JSONValue) async throws -> Flag {
        try await single(key, defaultValue: FlagValue.json(defaultValue))
    }

    /// Returns a new flag manager with the supplied evaluation context.
    public func withContext(_ context: Context) -> FlagManager {
        FlagManager(
            apiClient: apiClient,
            cache: cache,
            ruleEngine: ruleEngine,
            cacheTTL: cacheTTL,
            logger: logger,
            store: store,
            context: context,
            defaults: defaults
        )
    }

    /// Returns a new flag manager with the supplied defaults collection.
    public func withDefaults(_ defaults: DefaultsCollection) -> FlagManager {
        FlagManager(
            apiClient: apiClient,
            cache: cache,
            ruleEngine: ruleEngine,
            cacheTTL: cacheTTL,
            logger: logger,
            store: store,
            context: context,
            defaults: defaults
        )
    }

    /// Reports usage for a specific flag key.
    public func reportUsage(_ key: String, context: Context? = nil, defaultValue: FlagValue? = nil) {
        apiClient.reportUsage(key: key, context: context, defaultValue: defaultValue)
    }

    /// Forces the rules cache to refresh from the network.
    public func refreshRules() async throws {
        logger.info("Refreshing rules from API", metadata: nil)
        store.clear()
        _ = try await loadRulesFromAPI()
    }

    private func usageContext() -> Context? {
        context.isAnonymousWithoutData ? nil : context
    }

    /// Resolves the default value that should be reported for usage tracking:
    /// the inline parameter if provided, otherwise a `DefaultsCollection` entry.
    private func resolveEffectiveDefault(key: String, defaultValue: FlagValue?) -> FlagValue? {
        defaultValue ?? defaults.get(key)
    }

    private func ensureRulesLoaded() async throws -> [Flag] {
        if let flags = store.currentFlags() {
            return flags
        }

        if let cachedRules = try? cache.get(Self.cacheKey), let flags = try? decodeCachedFlags(cachedRules) {
            logger.debug("Loaded rules from cache", metadata: ["flag_count": "\(flags.count)"])
            store.setFlags(flags)
            return flags
        }

        return try await loadRulesFromAPI()
    }

    private func loadRulesFromAPI() async throws -> [Flag] {
        logger.info("Fetching rules from API", metadata: nil)

        let envelope = try await apiClient.getRules()
        store.setFlags(envelope.flags)

        do {
            let payload = try JSONEncoder().encode(envelope)
            if let serialized = String(data: payload, encoding: .utf8) {
                try cache.set(Self.cacheKey, value: serialized, ttl: cacheTTL)
            }
        } catch {
            logger.warn("Failed to cache rules", metadata: ["error": error.localizedDescription])
        }

        return envelope.flags
    }

    private func decodeCachedFlags(_ serialized: String) throws -> [Flag] {
        guard let data = serialized.data(using: .utf8) else {
            throw ZenmanageError.cache("Cached rules are not valid UTF-8")
        }

        let decoder = JSONDecoder()
        decoder.userInfo[.zenmanageLogger] = logger
        return try decoder.decode(RulesEnvelope.self, from: data).flags
    }

    private func evaluateFlag(_ flag: Flag) throws -> Flag {
        let selectedTarget: FlagTarget
        let selectedRules: [Rule]

        if let rollout = flag.rollout, try RolloutBucketer.isInBucket(salt: rollout.salt, contextIdentifier: context.identifier, percentage: rollout.percentage) {
            selectedTarget = rollout.target
            selectedRules = rollout.rules
        } else {
            selectedTarget = flag.target
            selectedRules = flag.rules
        }

        if selectedRules.isEmpty {
            return flag.with(target: selectedTarget, rules: selectedRules)
        }

        if let matchedRule = ruleEngine.evaluate(selectedRules, context: context) {
            let newTarget = FlagTarget(
                version: selectedTarget.version,
                expiredAt: selectedTarget.expiredAt,
                publishedAt: selectedTarget.publishedAt,
                scheduledAt: selectedTarget.scheduledAt,
                value: matchedRule.value
            )

            return flag.with(target: newTarget, rules: selectedRules)
        }

        return flag.with(target: selectedTarget, rules: selectedRules)
    }

    private func createFlagFromDefault(key: String, value: FlagValue) -> Flag {
        let type: FlagType

        switch value {
        case .boolean:
            type = .boolean
        case .string:
            type = .string
        case .number:
            type = .number
        case .json:
            type = .json
        case .unknown:
            type = .unknown
        }

        return Flag(
            version: "default",
            type: type,
            key: key,
            name: key,
            target: FlagTarget(version: "default", value: value)
        )
    }
}