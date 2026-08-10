import Foundation

/// A sensitive value that must never appear **raw** in a log (#41). It carries **only its category** —
/// never the underlying value — so raw health, precise location, calendar text, journal text, LLM
/// prompts, or raw sensor samples are **structurally impossible to log**, in every build. A caller
/// passes `Redacted(.health)` in place of the raw reading; the log renders `<redacted:health>`.
struct Redacted: Sendable, Equatable, Hashable {
    /// The #41-enumerated sensitive categories that must never be logged raw.
    enum Category: String, Sendable, Equatable, Hashable, CaseIterable {
        case health, location, calendar, journal, prompt, sample
    }

    let category: Category

    init(_ category: Category) {
        self.category = category
    }

    /// The coarse marker logged in place of the value — the category only.
    var marker: String { "<redacted:\(category.rawValue)>" }
}

/// Severity of a structured log event.
enum LogLevel: String, Sendable, Equatable, CaseIterable {
    case debug, info, notice, error, fault
}

/// One structured field. Non-sensitive values (`text`/`number`) render verbatim; a `redacted` field
/// renders only its category marker — the raw value is never held here, so it cannot leak.
enum LogField: Sendable, Equatable {
    case text(String, String)
    case number(String, Int)
    case redacted(String, Redacted)

    var rendered: String {
        switch self {
        case .text(let key, let value): "\(key)=\(value)"
        case .number(let key, let value): "\(key)=\(value)"
        case .redacted(let key, let redacted): "\(key)=\(redacted.marker)"
        }
    }
}

/// Renders a log line from a **`StaticString`** message (compile-time only — no runtime data, sensitive
/// or otherwise, can be interpolated into it) plus structured fields. Single-sourced so every backend
/// redacts identically.
enum LogLine {
    static func render(_ level: LogLevel, _ message: StaticString, _ fields: [LogField]) -> String {
        let head = "[\(level.rawValue)] \(message)"
        guard !fields.isEmpty else { return head }
        return head + " " + fields.map(\.rendered).joined(separator: " ")
    }
}

/// The privacy-safe structured-logging port (WG-019). The message is a `StaticString` so dynamic data
/// must go through `fields`, where anything sensitive must be a `Redacted` (which never carries the raw
/// value). The app composes a real `os.Logger`-backed logger; tests use an in-memory one. Redaction is
/// structural — release **and** debug logs omit raw health/location/calendar/journal/prompt values.
protocol PrivacyLog: Sendable {
    func log(_ level: LogLevel, _ message: StaticString, fields: [LogField])
}

extension PrivacyLog {
    func debug(_ message: StaticString, _ fields: [LogField] = []) {
        log(.debug, message, fields: fields)
    }
    func info(_ message: StaticString, _ fields: [LogField] = []) {
        log(.info, message, fields: fields)
    }
    func notice(_ message: StaticString, _ fields: [LogField] = []) {
        log(.notice, message, fields: fields)
    }
    func error(_ message: StaticString, _ fields: [LogField] = []) {
        log(.error, message, fields: fields)
    }
    func fault(_ message: StaticString, _ fields: [LogField] = []) {
        log(.fault, message, fields: fields)
    }
}
