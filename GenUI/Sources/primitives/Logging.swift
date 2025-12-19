//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Log levels used by the GenUI logger.
/// Higher levels indicate more severe messages.
public enum GenUiLogLevel: Int, Comparable, CaseIterable {
    case all = 0
    case finest = 1
    case finer = 2
    case fine = 3
    case info = 4
    case warning = 5
    case severe = 6
    case off = 7

    public var name: String {
        switch self {
        case .all: return "ALL"
        case .finest: return "FINEST"
        case .finer: return "FINER"
        case .fine: return "FINE"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .severe: return "SEVERE"
        case .off: return "OFF"
        }
    }

    /// Compares log levels by severity.
    /// Lower raw values are less severe.
    public static func < (lhs: GenUiLogLevel, rhs: GenUiLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Simple logger used throughout GenUI.
/// Formats messages and routes them through a handler.
public final class GenUiLogger {
    public let name: String
    public var level: GenUiLogLevel
    public var handler: ((GenUiLogLevel, String) -> Void)?

    /// Creates a logger with a name and initial level.
    /// Provide a handler to control log output.
    public init(name: String, level: GenUiLogLevel = .info) {
        self.name = name
        self.level = level
    }

    /// Logs a message at the specified level.
    /// Invokes the handler when the level is enabled.
    public func log(_ level: GenUiLogLevel, _ message: @autoclosure () -> String) {
        guard level >= self.level, level != .off else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        handler?(level, "[\(level.name)] \(timestamp): \(message())")
    }

    /// Logs a message at the finest level.
    /// Use for verbose tracing.
    public func finest(_ message: @autoclosure () -> String) { log(.finest, message()) }
    /// Logs a message at the finer level.
    /// Use for detailed tracing.
    public func finer(_ message: @autoclosure () -> String) { log(.finer, message()) }
    /// Logs a message at the fine level.
    /// Use for normal debugging.
    public func fine(_ message: @autoclosure () -> String) { log(.fine, message()) }
    /// Logs an informational message.
    /// Use for high-level flow events.
    public func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    /// Logs a warning message.
    /// Use for recoverable issues.
    public func warning(_ message: @autoclosure () -> String) { log(.warning, message()) }
    /// Logs a severe error message.
    /// Use for failures that need attention.
    public func severe(_ message: @autoclosure () -> String) { log(.severe, message()) }
}

public let genUiLogger = GenUiLogger(name: "GenUI")

@discardableResult
/// Configures the global GenUI logger.
/// Sets the log level and output callback.
public func configureGenUiLogging(
    level: GenUiLogLevel = .info,
    logCallback: ((GenUiLogLevel, String) -> Void)? = nil
) -> GenUiLogger {
    genUiLogger.level = level
    genUiLogger.handler = logCallback ?? { _, message in
        print(message)
    }
    return genUiLogger
}
