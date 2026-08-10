import Foundation

/// Which permissions onboarding may request (WG-200). Onboarding asks for **alarm essentials only**; every
/// optional data permission is **feature-triggered** — requested later, in context, when the user turns the
/// feature on — never up front. This keeps first-run friction minimal and consent contextual (#37).
enum OnboardingPlan {
    /// Requested during onboarding — the two capabilities an alarm needs.
    static let essentials: [ConsentCategory] = [.alarm, .notifications]

    /// Requested only when the user enables the feature, never during onboarding.
    static let featureTriggered: [ConsentCategory] = [
        .motion, .location, .health, .calendar, .cloudAI,
    ]

    static func isRequestedAtOnboarding(_ category: ConsentCategory) -> Bool {
        essentials.contains(category)
    }
}

/// A step in progressive onboarding (WG-200). Only essentials are gathered; the first-alarm step is
/// **skippable** and the app stays useful without it.
enum OnboardingStep: String, Sendable, Equatable, Hashable, CaseIterable {
    case welcome
    case enableAlarms
    case createFirstAlarm
    case ready

    /// Only the first-alarm step may be skipped — the user can always add an alarm later.
    var isSkippable: Bool { self == .createFirstAlarm }
}
