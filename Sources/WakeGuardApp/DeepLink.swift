import Foundation

/// A deep link decoded into a **navigational** route (WG-049). A route can only *select a screen*
/// — it can never carry an alarm mutation, so opening a link (from a notification, an AlarmKit
/// action, or a widget) never changes an alarm on its own (#7). A malformed, unknown, or
/// unsupported link decodes to `.unknown`, which the app surfaces as a safe error rather than
/// acting on it.
enum DeepLinkRoute: Equatable, Sendable {
    case alarm(AlarmID)
    /// Proposals aren't persisted or reviewable yet (E09); the app shows a safe "not available"
    /// state. Carries only an opaque id, never a command.
    case proposal(UUID)
    case unknown
}

/// Parses an incoming `URL` into a `DeepLinkRoute`. Pure and **total**: every URL maps to some
/// route, and anything that isn't an exact, well-formed match is `.unknown` — never a crash and
/// never a mutation. Links look like `wakeguard://alarm/<uuid>` or `wakeguard://proposal/<uuid>`.
enum DeepLinkParser {
    static let scheme = "wakeguard"

    static func route(for url: URL) -> DeepLinkRoute {
        guard url.scheme?.lowercased() == scheme else { return .unknown }
        // Exactly one path component — the id. Reject anything longer so a crafted link with
        // extra segments can't be coerced into a target.
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 1, let uuid = UUID(uuidString: components[0]) else {
            return .unknown
        }
        switch url.host()?.lowercased() {
        case "alarm": return .alarm(AlarmID(uuid))
        case "proposal": return .proposal(uuid)
        default: return .unknown
        }
    }
}
