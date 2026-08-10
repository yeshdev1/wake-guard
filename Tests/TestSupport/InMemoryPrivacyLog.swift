import Foundation

@testable import WakeGuard

/// An in-memory `PrivacyLog` for tests: records the rendered lines so redaction can be asserted. It uses
/// the **same** `LogLine.render` as the real `SystemPrivacyLog`, so a test proving no raw value leaks
/// here proves it for production too. Thread-safe.
final class InMemoryPrivacyLog: PrivacyLog {
    private let state = Synchronized([String]())

    var lines: [String] { state.get() }

    func log(_ level: LogLevel, _ message: StaticString, fields: [LogField]) {
        let line = LogLine.render(level, message, fields)
        state.mutate { $0.append(line) }
    }
}
