/// App-level feature flags and kill switches (ARCHITECTURE §10). Defaults are
/// privacy-first: every smart/optional feature is **off** (opt-in), and cloud AI
/// is off per ADR-004 (on-device only for the MVP).
///
/// `smartFeaturesKillSwitch` may disable smart behavior, but it must **never**
/// disable existing scheduled alarms (ARCHITECTURE §10) — that guarantee is
/// enforced by the scheduling/alarm code, not by this value.
struct AppSettings: Codable, Sendable, Equatable, Hashable {
    var preAlarmPromptEnabled: Bool
    var automaticProposalPreparationEnabled: Bool
    var cloudAIEnabled: Bool
    var locationContextEnabled: Bool
    var readinessScoreEnabled: Bool
    var experimentalAntiCheatEnabled: Bool
    var analyticsEnabled: Bool
    var smartFeaturesKillSwitch: Bool
    /// How much autonomy the advisory agent has (WG-171). Privacy-first default: recommend-only.
    var agentPermissionMode: AgentPermissionMode
    /// **Separate, explicit** consent to send minimized data to an optional cloud model (WG-174) — distinct
    /// from `cloudAIEnabled`. Cloud use requires **both** the feature flag *and* this consent; default off.
    var cloudAIConsented: Bool
    /// Opt-in to leave **redacted** crash breadcrumbs (WG-221). Off by default; even when on, breadcrumbs
    /// carry no raw sensitive data (only coarse categories + audit correlation IDs).
    var crashDiagnosticsEnabled: Bool
    /// Whether the first-launch onboarding has been completed (WG-200 composition). Persisted so the intro
    /// shows once, not every launch. Default false (a fresh install shows onboarding).
    var hasCompletedOnboarding: Bool

    static let `default` = AppSettings(
        preAlarmPromptEnabled: false,
        automaticProposalPreparationEnabled: false,
        cloudAIEnabled: false,
        locationContextEnabled: false,
        readinessScoreEnabled: false,
        experimentalAntiCheatEnabled: false,
        analyticsEnabled: false,
        smartFeaturesKillSwitch: false,
        agentPermissionMode: .recommendOnly,
        cloudAIConsented: false,
        crashDiagnosticsEnabled: false,
        hasCompletedOnboarding: false)
}

extension AppSettings {
    /// Backward-compatible decode: `agentPermissionMode` (WG-171) was added after the first release, so a
    /// stored blob without it decodes to the privacy-first `.recommendOnly` default rather than throwing.
    /// The other keys were always encoded, so they remain required. `encode(to:)` stays synthesized.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preAlarmPromptEnabled = try container.decode(Bool.self, forKey: .preAlarmPromptEnabled)
        automaticProposalPreparationEnabled = try container.decode(
            Bool.self, forKey: .automaticProposalPreparationEnabled)
        cloudAIEnabled = try container.decode(Bool.self, forKey: .cloudAIEnabled)
        locationContextEnabled = try container.decode(Bool.self, forKey: .locationContextEnabled)
        readinessScoreEnabled = try container.decode(Bool.self, forKey: .readinessScoreEnabled)
        experimentalAntiCheatEnabled = try container.decode(
            Bool.self, forKey: .experimentalAntiCheatEnabled)
        analyticsEnabled = try container.decode(Bool.self, forKey: .analyticsEnabled)
        smartFeaturesKillSwitch = try container.decode(Bool.self, forKey: .smartFeaturesKillSwitch)
        agentPermissionMode =
            try container.decodeIfPresent(AgentPermissionMode.self, forKey: .agentPermissionMode)
            ?? .recommendOnly
        cloudAIConsented =
            try container.decodeIfPresent(Bool.self, forKey: .cloudAIConsented) ?? false
        crashDiagnosticsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .crashDiagnosticsEnabled) ?? false
        hasCompletedOnboarding =
            try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }
}
