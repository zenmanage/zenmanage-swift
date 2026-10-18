import Foundation

private struct MetadataEnvelope: Decodable {
    let data: MetadataData

    struct MetadataData: Decodable {
        let cdn: String
        let path: String
    }
}

final class APIClient {
    private static let sdkVersion = "0.1.0"
    private static let defaultClientAgent = "zenmanage-swift"
    private static let maxRetries = 3
    private static let retryDelayNanoseconds: UInt64 = 100_000_000

    private let environmentToken: String
    private let apiEndpoint: URL
    private let enableUsageReporting: Bool
    private let logger: any ZenmanageLogger
    private let urlSession: URLSession
    private let clientAgent: String
    private let requestTimeout: TimeInterval
    private let decoder = JSONDecoder()

    init(configuration: ZenmanageConfiguration) {
        environmentToken = configuration.environmentToken
        apiEndpoint = configuration.apiEndpoint
        enableUsageReporting = configuration.enableUsageReporting
        logger = configuration.logger
        urlSession = configuration.urlSession
        clientAgent = configuration.clientAgent ?? Self.defaultClientAgent
        requestTimeout = configuration.requestTimeout
        decoder.userInfo[.zenmanageLogger] = logger
    }

    func getRules() async throws -> RulesEnvelope {
        var lastError: Error?

        for attempt in 0..<Self.maxRetries {
            do {
                if attempt > 0 {
                    let delay = Self.retryDelayNanoseconds * UInt64(1 << (attempt - 1))
                    logger.debug("Retrying rules fetch", metadata: ["attempt": "\(attempt + 1)", "delay_ns": "\(delay)"])
                    try await Task.sleep(nanoseconds: delay)
                }

                let rulesURL = try await getCdnRulesURL()
                logger.debug("Fetching rules from CDN", metadata: ["url": rulesURL.absoluteString])
                let rulesRequest = makeRequest(url: rulesURL, includeContentType: false)
                let rulesData = try await perform(request: rulesRequest)
                let envelope = try decoder.decode(RulesEnvelope.self, from: rulesData)

                logger.info("Successfully fetched rules", metadata: ["flag_count": "\(envelope.flags.count)"])
                return envelope
            } catch {
                lastError = error
                logger.warn("Failed to fetch rules", metadata: ["attempt": "\(attempt + 1)", "error": error.localizedDescription])
            }
        }

        throw ZenmanageError.fetchRules("Failed to fetch rules after \(Self.maxRetries) attempts: \(lastError?.localizedDescription ?? "unknown error")")
    }

    func reportUsage(key: String, context: Context?, defaultValue: FlagValue? = nil) {
        guard enableUsageReporting else {
            logger.debug("Usage reporting disabled", metadata: ["key": key])
            return
        }

        Task {
            do {
                try await sendUsage(key: key, context: context, defaultValue: defaultValue)
            } catch {
                logger.debug("Failed to report usage", metadata: ["key": key, "error": error.localizedDescription])
            }
        }
    }

    private func sendUsage(key: String, context: Context?, defaultValue: FlagValue?) async throws {
        let url = apiEndpoint.appendingPathComponent("v1/flags/\(key)/usage")
        var request = makeRequest(url: url, timeout: min(requestTimeout, ZenmanageConfiguration.usageReportTimeout))
        request.httpMethod = "POST"

        if let context, !context.isAnonymousWithoutData {
            let encoder = JSONEncoder()
            request.setValue(String(data: try encoder.encode(context), encoding: .utf8), forHTTPHeaderField: "X-ZEN-CONTEXT")
        }

        if let defaultValue {
            do {
                let payload = try JSONEncoder().encode([key: defaultValue])
                request.setValue(String(data: payload, encoding: .utf8), forHTTPHeaderField: "X-ZEN-DEFAULT-VALUE")
            } catch {
                logger.debug("Failed to encode usage default value", metadata: ["key": key, "error": error.localizedDescription])
            }
        }

        _ = try await perform(request: request)
    }

    private func getCdnRulesURL() async throws -> URL {
        let metadataURL = apiEndpoint.appendingPathComponent("v1/flag-json")
        logger.debug("Fetching rules metadata", metadata: ["url": metadataURL.absoluteString])

        let data = try await perform(request: makeRequest(url: metadataURL))
        let metadata = try decoder.decode(MetadataEnvelope.self, from: data)

        guard let cdnURL = URL(string: metadata.data.cdn + metadata.data.path) else {
            throw ZenmanageError.invalidRules("API response contained an invalid CDN URL")
        }

        return cdnURL
    }

    private func makeRequest(url: URL, includeContentType: Bool = true, timeout: TimeInterval? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout ?? requestTimeout
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(environmentToken, forHTTPHeaderField: "X-ZEN-API-KEY")
        request.setValue("\(clientAgent)/\(Self.sdkVersion)", forHTTPHeaderField: "X-ZEN-CLIENT-AGENT")

        if includeContentType {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func perform(request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZenmanageError.fetchRules("Invalid HTTP response from Zenmanage API")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ZenmanageError.fetchRules("Request failed with status \(httpResponse.statusCode)")
        }

        return data
    }
}