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

    static let `default` = AppSettings(
        preAlarmPromptEnabled: false,
        automaticProposalPreparationEnabled: false,
        cloudAIEnabled: false,
        locationContextEnabled: false,
        readinessScoreEnabled: false,
        experimentalAntiCheatEnabled: false,
        analyticsEnabled: false,
        smartFeaturesKillSwitch: false)
}
