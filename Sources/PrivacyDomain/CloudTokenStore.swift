import Foundation

/// Stores the optional cloud-AI access token (WG-185). The token is a `Sensitive<String>` (WG-181), so it
/// **cannot be logged** through normal APIs; it is **revocable** (`revoke()` removes it); and it is meant
/// to live in the **Keychain**, never in source or `UserDefaults`. The domain owns the port; the real
/// Keychain-backed store is infrastructure.
protocol CloudTokenStore: Sendable {
    func token() async -> Sensitive<String>?
    func store(_ token: Sensitive<String>) async throws
    /// Revoke (delete) the stored token — cloud access can always be turned off.
    func revoke() async throws
    func hasToken() async -> Bool
}

/// A non-persistent, in-memory `CloudTokenStore` for previews and tests (WG-185). It keeps the token only
/// in memory (never on disk), so it is unsuitable for production — the Keychain-backed store is used there.
actor InMemoryCloudTokenStore: CloudTokenStore {
    private var stored: Sensitive<String>?

    init(_ initial: Sensitive<String>? = nil) {
        stored = initial
    }

    func token() -> Sensitive<String>? { stored }

    func store(_ token: Sensitive<String>) { stored = token }

    func revoke() { stored = nil }

    func hasToken() -> Bool { stored != nil }
}
