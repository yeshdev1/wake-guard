import Foundation
import Observation

/// Drives progressive onboarding (WG-200): welcome → enable alarms (essentials only) → optionally create a
/// first alarm → ready. Optional data permissions are **never** requested here — they are feature-triggered
/// later. The first-alarm step is **skippable**, and skipping still completes onboarding into a fully
/// usable app. Holds no alarm authority.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var step: OnboardingStep = .welcome
    private(set) var skippedFirstAlarm = false

    var isComplete: Bool { step == .ready }
    var canSkip: Bool { step.isSkippable }

    /// Advance to the next step (no-op at `.ready`).
    func advance() {
        switch step {
        case .welcome: step = .enableAlarms
        case .enableAlarms: step = .createFirstAlarm
        case .createFirstAlarm: step = .ready
        case .ready: break
        }
    }

    /// Skip the current step if it is skippable, still advancing to a usable state.
    func skip() {
        guard step.isSkippable else { return }
        if step == .createFirstAlarm { skippedFirstAlarm = true }
        advance()
    }
}
