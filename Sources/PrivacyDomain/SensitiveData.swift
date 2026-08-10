import Foundation

/// A value marked **sensitive** (WG-181) — health samples, precise location, calendar titles, journal
/// text, prompts. It **cannot be read through any normal logging API**: `description`, `debugDescription`,
/// `String(describing:)`, string interpolation, and even `dump`/`Mirror` all render `"<redacted>"`. The
/// raw value is reachable **only** through the explicit, auditable `reveal()` — so an accidental
/// `log("\(x)")` / `print(x)` / `dump(x)` can never leak it (#41).
struct Sensitive<Value: Sendable>: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private let value: Value

    init(_ value: Value) {
        self.value = value
    }

    /// The one explicit, auditable way to read the raw value. Call sites are intentionally greppable.
    func reveal() -> Value { value }

    var description: String { "<redacted>" }
    var debugDescription: String { "<redacted>" }
    /// Redacts reflection too, so `dump`/`Mirror` can't walk to the private value.
    var customMirror: Mirror { Mirror(self, children: ["value": "<redacted>"]) }
}

extension Sensitive: Equatable where Value: Equatable {}
extension Sensitive: Hashable where Value: Hashable {}

/// A value that has been **cleared** (redacted) for external (e.g. cloud) use (WG-181). It is constructible
/// **only** through `Redaction.redact(_:using:)` — its initializer is `fileprivate` — so a raw or
/// `Sensitive` value can never masquerade as cleared. A compiler boundary: functions that transmit data
/// off-device take `Cleared<…>`, and there is no way to hand them un-redacted data. (Distinct from the
/// privacy-log `Redacted` marker in Observability.)
struct Cleared<Value: Sendable>: Sendable {
    let value: Value

    fileprivate init(cleared value: Value) {
        self.value = value
    }
}

/// The redaction boundary (WG-181): the sole factory for `Cleared` values.
enum Redaction {
    /// Produce a `Cleared` projection of a sensitive value by applying an explicit `transform` that strips
    /// the sensitive parts. The transform is where redaction happens; its output is what may leave the
    /// device.
    static func redact<Source, Projection: Sendable>(
        _ sensitive: Sensitive<Source>, using transform: (Source) -> Projection
    ) -> Cleared<Projection> {
        Cleared(cleared: transform(sensitive.reveal()))
    }
}
