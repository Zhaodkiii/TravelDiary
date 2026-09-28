import Foundation
import os

enum LogLevel: Int, CaseIterable, Codable, Sendable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4

    nonisolated var symbol: String {
        switch self {
        case .verbose: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

/// 统一日志模块标识（大写英文，下划线风格与控制台输出一致）。
enum LogModule: String, Sendable, CaseIterable {
    case app = "APP"
    case auth = "AUTH"
    case network = "NETWORK"
    case device = "DEVICE"
    case cache = "CACHE"
    case oss = "OSS"
    case aiConfig = "AI_CONFIG"
    case database = "DATABASE"
    case notification = "NOTIFICATION"
    case lifecycle = "LIFECYCLE"
    case file = "FILE"
    case ocr = "OCR"
    case routing = "ROUTING"
    case camera = "CAMERA"
    case aiChat = "AI_CHAT"
    case general = "GENERAL"
}

/// 长文本日志安全截断（OCR、JSON、调试摘要等）。
enum LogMessageSanitizer: Sendable {
    nonisolated(unsafe) static let maxLogSnippetLength = 200

    nonisolated static func singleLineSnippet(_ text: String, limit: Int = maxLogSnippetLength) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        guard collapsed.count > limit else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: limit, limitedBy: collapsed.endIndex) ?? collapsed.endIndex
        return String(collapsed[..<end]) + "…(len=\(collapsed.count))"
    }
}

typealias InternalLogHandler = @Sendable (
    _ level: LogLevel,
    _ module: LogModule,
    _ message: String
) -> Void

nonisolated(unsafe) private let supportLogLevelStorage = Atomic<LogLevel>(.info)
nonisolated(unsafe) private let supportLogHandlerStorage = Atomic<InternalLogHandler>(SupportLogger.defaultHandler)
nonisolated(unsafe) private let supportLogSubsystemStorage = Atomic<String>("TravelDiary")

/// 网络与基础设施统一日志中心。
enum SupportLogger {
    nonisolated static var logLevel: LogLevel {
        get { supportLogLevelStorage.value }
        set { supportLogLevelStorage.value = newValue }
    }

    /// 保留字段（兼容旧配置）；默认输出格式不再包含 subsystem。
    nonisolated static var subsystem: String {
        get { supportLogSubsystemStorage.value }
        set { supportLogSubsystemStorage.value = newValue }
    }

    nonisolated static func configure(
        level: LogLevel,
        subsystem: String? = nil,
        handler: InternalLogHandler? = nil
    ) {
        supportLogLevelStorage.value = level
        if let subsystem {
            supportLogSubsystemStorage.value = subsystem
        }
        if let handler {
            supportLogHandlerStorage.value = handler
        }
    }

    nonisolated static func reset() {
        supportLogLevelStorage.value = .info
        supportLogSubsystemStorage.value = "TravelDiary"
        supportLogHandlerStorage.value = defaultHandler
    }

    nonisolated static func isEnabled(_ level: LogLevel) -> Bool {
        level.rawValue >= supportLogLevelStorage.value.rawValue
    }

    nonisolated static func log(
        level: LogLevel,
        module: LogModule,
        message: String
    ) {
        guard isEnabled(level) else { return }
        supportLogHandlerStorage.value(level, module, message)
    }

    nonisolated fileprivate static func defaultHandler(
        level: LogLevel,
        module: LogModule,
        message: String
    ) {
        if #available(iOS 14.0, macOS 11.0, *) {
            let logger = os.Logger(subsystem: supportLogSubsystemStorage.value, category: module.rawValue)
            switch level {
            case .verbose:
                logger.trace("\(message, privacy: .public)")
            case .debug:
                logger.debug("\(message, privacy: .public)")
            case .info:
                logger.info("\(message, privacy: .public)")
            case .warning:
                logger.warning("\(message, privacy: .public)")
            case .error:
                logger.error("\(message, privacy: .public)")
            }
            return
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)][\(module.rawValue)][\(level.symbol)] \(message)")
    }
}

/// 轻量日志协议；每条日志单行，模块使用 `LogModule`。
nonisolated protocol Logger: Sendable {
    nonisolated func verbose(_ message: String, module: LogModule)
    nonisolated func debug(_ message: String, module: LogModule)
    nonisolated func info(_ message: String, module: LogModule)
    nonisolated func warning(_ message: String, module: LogModule)
    nonisolated func error(_ message: String, module: LogModule)
}

nonisolated extension Logger {
    func verbose(_ message: String) {
        verbose(message, module: .general)
    }

    func debug(_ message: String) {
        debug(message, module: .general)
    }

    func info(_ message: String) {
        info(message, module: .general)
    }

    func warning(_ message: String) {
        warning(message, module: .general)
    }

    func error(_ message: String) {
        error(message, module: .general)
    }
}

nonisolated struct ConsoleLogger: Logger {
    nonisolated func verbose(_ message: String, module: LogModule) {
        SupportLogger.log(level: .verbose, module: module, message: message)
    }

    nonisolated func debug(_ message: String, module: LogModule) {
        SupportLogger.log(level: .debug, module: module, message: message)
    }

    nonisolated func info(_ message: String, module: LogModule) {
        SupportLogger.log(level: .info, module: module, message: message)
    }

    nonisolated func warning(_ message: String, module: LogModule) {
        SupportLogger.log(level: .warning, module: module, message: message)
    }

    nonisolated func error(_ message: String, module: LogModule) {
        SupportLogger.log(level: .error, module: module, message: message)
    }
}
