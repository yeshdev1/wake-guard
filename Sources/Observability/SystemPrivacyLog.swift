import os

/// The real `PrivacyLog` (WG-019), backed by the unified logging system (`os.Logger`). It logs the
/// pre-rendered safe line as `.public` — correct precisely because the line is built only from a
/// `StaticString` message, non-sensitive fields, and `Redacted` markers (never a raw value). The one
/// place `os` is touched for app logging; the redaction guarantee is single-sourced in `LogLine`.
struct SystemPrivacyLog: PrivacyLog {
    private let logger: os.Logger

    init(subsystem: String = "com.wakeguard.app", category: String) {
        logger = os.Logger(subsystem: subsystem, category: category)
    }

    func log(_ level: LogLevel, _ message: StaticString, fields: [LogField]) {
        let line = LogLine.render(level, message, fields)
        // `.public` is safe: `line` contains no raw sensitive value by construction (a `Redacted`
        // carries only its category), so marking it public keeps the safe fields legible in Console
        // rather than collapsing them to `<private>`.
        logger.log(level: Self.osLogType(level), "\(line, privacy: .public)")
    }

    private static func osLogType(_ level: LogLevel) -> OSLogType {
        switch level {
        case .debug: .debug
        case .info: .info
        case .notice: .default
        case .error: .error
        case .fault: .fault
        }
    }
}
