import Foundation

/// The display content for the tomorrow-plan screen (WG-146). Structured, testable data — the SwiftUI
/// view renders it. The **existing alarm is always exposed** (`existingAlarmRing`) so it can never be
/// hidden by a recommendation; the recommendation carries its **reason** and **buffer** breakdown; and it
/// holds **no apply action** — applying is a discrete user action wired at the view (never automatic).
struct TomorrowPlanPresentation: Sendable, Equatable {
    /// The current alarm's next ring — always shown so the existing alarm stays visible (`nil` = none set).
    let existingAlarmRing: Date?
    /// The recommendation, or `nil` when there's nothing to plan around.
    let recommendation: Recommendation?

    struct Recommendation: Sendable, Equatable {
        let recommendedWake: Date
        let bindingEventStart: Date
        /// Why this time — no formatted clock (so it's locale-stable + testable); the view adds the times.
        let reason: String
        /// The buffer breakdown (getting-ready, travel if the event has a location, safety margin).
        let buffers: [BufferLine]
        /// The uncertainty phrasing (from the plan's confidence).
        let confidenceNote: String
        /// Whether the recommendation differs from the existing alarm (so the UI can highlight a change).
        let differsFromExistingAlarm: Bool
    }

    struct BufferLine: Sendable, Equatable, Hashable {
        let label: String
        let minutes: Int
    }
}

/// Builds the tomorrow-plan display content from a WG-145 plan + the profile + the existing alarm
/// (WG-146). Pure.
enum TomorrowPlanPresenter {
    static func present(
        plan: LatestSafeWakePlan?, profile: MorningPreparationProfile, existingAlarmRing: Date?
    ) -> TomorrowPlanPresentation {
        guard let plan else {
            return TomorrowPlanPresentation(
                existingAlarmRing: existingAlarmRing, recommendation: nil)
        }
        var buffers = [
            TomorrowPlanPresentation.BufferLine(
                label: "Getting ready", minutes: minutes(profile.preparationBuffer))
        ]
        if plan.bindingHasLocation {
            buffers.append(.init(label: "Travel", minutes: minutes(profile.travelBuffer)))
        }
        buffers.append(.init(label: "Safety margin", minutes: minutes(profile.safetyBuffer)))

        let differs =
            existingAlarmRing.map { abs($0.timeIntervalSince(plan.latestSafeWake)) >= 60 } ?? true
        return TomorrowPlanPresentation(
            existingAlarmRing: existingAlarmRing,
            recommendation: TomorrowPlanPresentation.Recommendation(
                recommendedWake: plan.latestSafeWake,
                bindingEventStart: plan.bindingEventStart,
                reason: reason(plan),
                buffers: buffers,
                confidenceNote: confidenceNote(plan.confidence, hasConflicts: plan.hasConflicts),
                differsFromExistingAlarm: differs))
    }

    private static func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }

    private static func reason(_ plan: LatestSafeWakePlan) -> String {
        plan.drivenByConfirmedImportant
            ? "This gets you ready in time for the event you marked as important, with your usual buffers."
            : "Based on your earliest event tomorrow — you haven't marked one as important, so treat this "
                + "as a rough guess."
    }

    private static func confidenceNote(_ confidence: WakePlanConfidence, hasConflicts: Bool)
        -> String
    {
        switch confidence {
        case .high: "You confirmed the key event, so this should be reliable."
        case .moderate:
            hasConflicts
                ? "Some of your events overlap, so it's worth a second look."
                : "This is a reasonable estimate."
        case .low: "Your events overlap and none is marked important — please double-check."
        }
    }
}
