import Foundation

/// Logging interface for SDK diagnostics.
public protocol ZenmanageLogger {
    func debug(_ message: String, metadata: [String: String]?)
    func info(_ message: String, metadata: [String: String]?)
    func warn(_ message: String, metadata: [String: String]?)
    func error(_ message: String, metadata: [String: String]?)
}

/// Default no-op logger.
public struct NullLogger: ZenmanageLogger {
    public init() {}

    public func debug(_ message: String, metadata: [String: String]? = nil) {}
    public func info(_ message: String, metadata: [String: String]? = nil) {}
    public func warn(_ message: String, metadata: [String: String]? = nil) {}
    public func error(_ message: String, metadata: [String: String]? = nil) {}
}

extension CodingUserInfoKey {
    /// Carries the configured `ZenmanageLogger` into `Decodable` initializers (via
    /// `JSONDecoder.userInfo`) so decode-time fallbacks, such as an unrecognized flag
    /// type or value, can be logged once instead of silently swallowed.
    static let zenmanageLogger = CodingUserInfoKey(rawValue: "com.zenmanage.swift.logger")!
}