import Foundation

/// A sensitivity classification for content bound for the cloud (WG-174). **Default-deny**: only content a
/// caller explicitly classifies `.nonSensitive` may ever leave the device.
enum CloudDataSensitivity: Sendable, Equatable, Hashable {
    case sensitive
    case nonSensitive
}

/// Text that has been explicitly cleared as **non-sensitive** for cloud transmission (WG-174). It is
/// constructible **only** through `CloudRedactor` — its initializer is private — so raw or sensitive text
/// cannot reach the cloud transport by accident. A compiler boundary, not a convention (#35).
struct CloudSafeText: Sendable, Equatable, Hashable {
    let value: String
    fileprivate init(cleared value: String) { self.value = value }
}

/// The **default-deny** redactor for cloud-bound content (WG-174). It refuses to clear anything not
/// explicitly classified `.nonSensitive`, so sensitive data can never be wrapped as `CloudSafeText`.
enum CloudRedactor {
    static func clear(_ text: String, classification: CloudDataSensitivity) -> CloudSafeText? {
        guard classification == .nonSensitive else { return nil }
        return CloudSafeText(cleared: text)
    }
}

/// A request that may be sent to the cloud (WG-174): both prompts are `CloudSafeText`, so — by
/// construction — no un-redacted content can be transmitted.
struct CloudSafeRequest: Sendable, Equatable, Hashable {
    let systemPrompt: CloudSafeText
    let userPrompt: CloudSafeText
}

/// The network transport for the optional cloud model (WG-174). It accepts **only** a `CloudSafeRequest`,
/// so a raw `LanguageModelRequest`/`String` can never be sent — the redaction boundary is enforced at the
/// type level. The real implementation (network) is out of MVP scope; this port lets it be swapped and
/// faked, and keeps domain code framework-free.
protocol CloudModelTransport: Sendable {
    func send(_ request: CloudSafeRequest) async throws(LanguageModelError) -> String
}

/// Decides whether the optional cloud model may be used (WG-174). Requires **both** the `cloudAIEnabled`
/// feature flag **and** the separate `cloudAIConsented` consent — either alone is not enough — and both
/// default off, so cloud is **disabled by default**.
struct CloudProviderGate: Sendable {
    func isCloudAvailable(settings: AppSettings) -> Bool {
        settings.cloudAIEnabled && settings.cloudAIConsented
    }
}

/// The optional cloud language-model client (WG-174). It sends **nothing** unless the gate allows (feature
/// enabled *and* separately consented) and can only be handed a `CloudSafeRequest` (default-deny
/// redaction). If cloud is not available it fails closed to `.unavailable` without touching the transport,
/// so the on-device pipeline's deterministic fallback (#33) takes over.
struct CloudLanguageModelClient: Sendable {
    private let gate: CloudProviderGate
    private let transport: any CloudModelTransport
    private let settings: @Sendable () -> AppSettings

    init(
        gate: CloudProviderGate = CloudProviderGate(), transport: any CloudModelTransport,
        settings: @escaping @Sendable () -> AppSettings
    ) {
        self.gate = gate
        self.transport = transport
        self.settings = settings
    }

    func generate(_ request: CloudSafeRequest) async throws(LanguageModelError) -> String {
        guard gate.isCloudAvailable(settings: settings()) else { throw .unavailable }
        return try await transport.send(request)
    }
}
