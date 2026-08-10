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

/// A value that has passed through the **redaction chokepoint** (WG-181). Its initializer is `fileprivate`,
/// so the **only** way to obtain a `Cleared` is `Redaction.redact(_:using:)` — a single, auditable call
/// site. It therefore proves *"a redaction step was invoked"*, **not** *"this content is safe"*: the
/// transform's correctness is the caller's responsibility (an identity/weak transform yields a `Cleared`
/// that still carries sensitive content — pinned by a test). Cloud-bound builders take `Cleared<…>` so
/// every transmitted value provably went through the chokepoint, keeping the *reviewable surface* to the
/// few redact sites.
///
/// NOTE: the **wired** cloud transmit boundary today is WG-174's `CloudSafeText`/`CloudSafeRequest`, not
/// `Cleared`; and the Observability `Redacted` marker is the log boundary. Reconciling the three into one
/// documented transmit chokepoint (e.g. deriving `CloudSafeText` from a `Cleared`) is a follow-up (WG-185/
/// 189). `Sensitive` is also not yet adopted at data sources — that migration is what shrinks the real
/// leak surface (WG-190 scans for residue).
struct Cleared<Value: Sendable>: Sendable {
    let value: Value

    fileprivate init(cleared value: Value) {
        self.value = value
    }
}

/// The redaction chokepoint (WG-181): the sole factory for `Cleared` values.
enum Redaction {
    /// Route a sensitive value through the chokepoint — apply `transform` to the revealed value and wrap the
    /// result as `Cleared`. The transform is where redaction **must** happen; `Cleared` guarantees the
    /// chokepoint was used, **not** that the output is safe, so redact call sites are deliberately few and
    /// reviewed. An identity transform is a known-unsafe pattern (test-pinned).
    static func redact<Source, Projection: Sendable>(
        _ sensitive: Sensitive<Source>, using transform: (Source) -> Projection
    ) -> Cleared<Projection> {
        Cleared(cleared: transform(sensitive.reveal()))
    }
}
