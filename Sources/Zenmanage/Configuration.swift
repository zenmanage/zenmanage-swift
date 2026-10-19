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
    /// Timeout, in seconds, applied to each rules request. Usage reports use the smaller
    /// of this and `ZenmanageConfiguration.usageReportTimeout`.
    public let requestTimeout: TimeInterval

    /// Upper bound, in seconds, for a fire-and-forget usage report.
    public static let usageReportTimeout: TimeInterval = 5
    /// Default for `requestTimeout`, shared with the other Zenmanage SDKs.
    public static let defaultRequestTimeout: TimeInterval = 10

    public init(
        environmentToken: String,
        cacheTTL: TimeInterval = 3600,
        cache: any RuleCache = UserDefaultsRuleCache(),
        enableUsageReporting: Bool = true,
        apiEndpoint: URL = URL(string: "https://api.zenmanage.com")!,
        logger: any ZenmanageLogger = NullLogger(),
        urlSession: URLSession = .shared,
        clientAgent: String? = nil,
        requestTimeout: TimeInterval = ZenmanageConfiguration.defaultRequestTimeout
    ) throws {
        guard !environmentToken.isEmpty else {
            throw ZenmanageError.configuration("Environment token is required")
        }

        // Server keys must never ship inside an app bundle, where anyone can extract them.
        guard !environmentToken.hasPrefix("srv_") else {
            throw ZenmanageError.configuration("Invalid environment token for iOS runtime: server key provided. Use a mobile key (mob_...) or client key (cli_...).")
        }

        guard environmentToken.hasPrefix("mob_") || environmentToken.hasPrefix("cli_") else {
            throw ZenmanageError.configuration("Invalid environment token for iOS runtime. Use a mobile key (mob_...) or client key (cli_...).")
        }

        guard cacheTTL >= 0 else {
            throw ZenmanageError.configuration("Cache TTL must be zero or greater")
        }

        guard requestTimeout > 0 else {
            throw ZenmanageError.configuration("Request timeout must be greater than zero")
        }

        self.environmentToken = environmentToken
        self.cacheTTL = cacheTTL
        self.cache = cache
        self.enableUsageReporting = enableUsageReporting
        self.apiEndpoint = apiEndpoint
        self.logger = logger
        self.urlSession = urlSession
        self.clientAgent = clientAgent
        self.requestTimeout = requestTimeout
    }
}