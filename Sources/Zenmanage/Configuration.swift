import Foundation

/// Configuration for the Zenmanage Swift SDK.
public final class ZenmanageConfiguration {
    public let environmentToken: String
    public let cacheTTL: TimeInterval
    public let cache: any RuleCache
    public let enableUsageReporting: Bool
    public let apiEndpoint: URL
    public let logger: any ZenmanageLogger
    public let urlSession: URLSession
    public let clientAgent: String?

    public init(
        environmentToken: String,
        cacheTTL: TimeInterval = 3600,
        cache: any RuleCache = UserDefaultsRuleCache(),
        enableUsageReporting: Bool = true,
        apiEndpoint: URL = URL(string: "https://api.zenmanage.com")!,
        logger: any ZenmanageLogger = NullLogger(),
        urlSession: URLSession = .shared,
        clientAgent: String? = nil
    ) throws {
        guard !environmentToken.isEmpty else {
            throw ZenmanageError.configuration("Environment token is required")
        }

        guard environmentToken.hasPrefix("mob_") || environmentToken.hasPrefix("srv_") else {
            throw ZenmanageError.configuration("Invalid environment token for iOS runtime. Use a mobile key (mob_...) or server key (srv_...).")
        }

        guard cacheTTL >= 0 else {
            throw ZenmanageError.configuration("Cache TTL must be zero or greater")
        }

        self.environmentToken = environmentToken
        self.cacheTTL = cacheTTL
        self.cache = cache
        self.enableUsageReporting = enableUsageReporting
        self.apiEndpoint = apiEndpoint
        self.logger = logger
        self.urlSession = urlSession
        self.clientAgent = clientAgent
    }
}