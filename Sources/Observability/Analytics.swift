import Foundation

/// An optional data feature, for analytics only (WG-220) — a closed enum, never a free string.
enum AnalyticsFeature: String, Sendable, Equatable, Hashable, CaseIterable {
    case motion, location, health, calendar, cloudAI
}

/// The scope of a deletion, for analytics only (WG-220).
enum AnalyticsDeletionScope: String, Sendable, Equatable, Hashable, CaseIterable {
    case optional, all
}

/// A coarse property value (WG-220). By construction it can only be a flag, a small **bucketed** count, or
/// a **closed-enum** category — **never** free text, so a sensitive value can't be smuggled into analytics.
enum AnalyticsValue: Sendable, Equatable, Hashable {
    case flag(Bool)
    case bucket(Int)
    case category(String)
}

/// A **closed** analytics event schema (WG-220). Every case carries only non-sensitive associated values
/// (a flag or a closed enum); there is **no** free-form `custom(name:payload:)` case, so the event stream
/// structurally **forbids sensitive payloads** — no health, location, titles, journal, or prompt text can
/// be represented, let alone transmitted.
enum AnalyticsEvent: Sendable, Equatable, Hashable {
    case alarmCreated(isCritical: Bool)
    case agentChangeApplied(confirmed: Bool)
    case challengeFinished(passed: Bool)
    case onboardingCompleted(skippedFirstAlarm: Bool)
    case optionalFeatureToggled(feature: AnalyticsFeature, enabled: Bool)
    case dataExportPrepared
    case dataDeleted(scope: AnalyticsDeletionScope)

    var name: String {
        switch self {
        case .alarmCreated: "alarm_created"
        case .agentChangeApplied: "agent_change_applied"
        case .challengeFinished: "challenge_finished"
        case .onboardingCompleted: "onboarding_completed"
        case .optionalFeatureToggled: "optional_feature_toggled"
        case .dataExportPrepared: "data_export_prepared"
        case .dataDeleted: "data_deleted"
        }
    }

    /// Coarse, non-sensitive properties derived from the case — only flags and closed-enum categories.
    var properties: [String: AnalyticsValue] {
        switch self {
        case .alarmCreated(let isCritical): ["is_critical": .flag(isCritical)]
        case .agentChangeApplied(let confirmed): ["confirmed": .flag(confirmed)]
        case .challengeFinished(let passed): ["passed": .flag(passed)]
        case .onboardingCompleted(let skipped): ["skipped_first_alarm": .flag(skipped)]
        case .optionalFeatureToggled(let feature, let enabled):
            ["feature": .category(feature.rawValue), "enabled": .flag(enabled)]
        case .dataExportPrepared: [:]
        case .dataDeleted(let scope): ["scope": .category(scope.rawValue)]
        }
    }
}

/// The analytics port (WG-220). It accepts **only** a closed `AnalyticsEvent` — there is no
/// string/dictionary API — so callers can't attach sensitive payloads. The default is a no-op (no SDK
/// needed for local development); a real backend would conform behind this same port.
protocol AnalyticsSink: Sendable {
    func record(_ event: AnalyticsEvent)
}

/// The default sink: records nothing. **No SDK is required** to build or run locally.
struct NoOpAnalyticsSink: AnalyticsSink {
    func record(_ event: AnalyticsEvent) {}
}

/// Wraps a sink and **gates it on a switch** (WG-220): when analytics is disabled, nothing is recorded at
/// all. Analytics is off by default (`AppSettings.analyticsEnabled == false`).
struct GatedAnalytics: AnalyticsSink {
    private let underlying: any AnalyticsSink
    private let isEnabled: @Sendable () -> Bool

    init(underlying: any AnalyticsSink, isEnabled: @escaping @Sendable () -> Bool) {
        self.underlying = underlying
        self.isEnabled = isEnabled
    }

    func record(_ event: AnalyticsEvent) {
        guard isEnabled() else { return }
        underlying.record(event)
    }
}
