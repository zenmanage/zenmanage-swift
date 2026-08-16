import Foundation

/// Errors thrown by the Zenmanage Swift SDK.
public enum ZenmanageError: LocalizedError, Equatable {
    case configuration(String)
    case evaluation(String)
    case fetchRules(String)
    case invalidRules(String)
    case cache(String)

    public var errorDescription: String? {
        switch self {
        case let .configuration(message),
             let .evaluation(message),
             let .fetchRules(message),
             let .invalidRules(message),
             let .cache(message):
            return message
        }
    }

    var nsError: NSError {
        let code: Int

        switch self {
        case .configuration:
            code = 1001
        case .evaluation:
            code = 1002
        case .fetchRules:
            code = 1003
        case .invalidRules:
            code = 1004
        case .cache:
            code = 1005
        }

        return NSError(
            domain: "com.zenmanage.swift",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: errorDescription ?? "Zenmanage error"]
        )
    }
}

extension Error {
    var zenmanageNSError: NSError {
        if let error = self as? ZenmanageError {
            return error.nsError
        }

        return self as NSError
    }
}