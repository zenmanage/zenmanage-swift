import Foundation

/// Main entry point for the Zenmanage Swift SDK.
public final class Zenmanage {
    private let flagManager: FlagManager

    public init(configuration: ZenmanageConfiguration) {
        let apiClient = APIClient(configuration: configuration)
        let ruleEngine = RuleEngine()

        flagManager = FlagManager(
            apiClient: apiClient,
            cache: configuration.cache,
            ruleEngine: ruleEngine,
            cacheTTL: configuration.cacheTTL,
            logger: configuration.logger
        )
    }

    public convenience init(
        environmentToken: String,
        cacheTTL: TimeInterval = 3600,
        cache: any RuleCache = UserDefaultsRuleCache(),
        enableUsageReporting: Bool = true,
        apiEndpoint: URL = URL(string: "https://api.zenmanage.com")!,
        logger: any ZenmanageLogger = NullLogger(),
        urlSession: URLSession = .shared,
        requestTimeout: TimeInterval = ZenmanageConfiguration.defaultRequestTimeout
    ) throws {
        let configuration = try ZenmanageConfiguration(
            environmentToken: environmentToken,
            cacheTTL: cacheTTL,
            cache: cache,
            enableUsageReporting: enableUsageReporting,
            apiEndpoint: apiEndpoint,
            logger: logger,
            urlSession: urlSession,
            requestTimeout: requestTimeout
        )

        self.init(configuration: configuration)
    }

    /// Returns the flag manager used for fetching and evaluating flags.
    public func flags() -> FlagManager {
        flagManager
    }
}