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

    static let `default` = AppSettings(
        preAlarmPromptEnabled: false,
        automaticProposalPreparationEnabled: false,
        cloudAIEnabled: false,
        locationContextEnabled: false,
        readinessScoreEnabled: false,
        experimentalAntiCheatEnabled: false,
        analyticsEnabled: false,
        smartFeaturesKillSwitch: false,
        agentPermissionMode: .recommendOnly)
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
    }
}
