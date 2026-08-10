import Foundation

/// How confident a latest-safe-wake plan is (WG-145). A **user-confirmed** critical event gives high
/// confidence; an *inferred* first event only moderate; overlapping (conflicting) events lower it a step
/// — so the result always carries its uncertainty. Buffers are user estimates, never precise.
enum WakePlanConfidence: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case low
    case moderate
    case high

    var downgraded: WakePlanConfidence {
        switch self {
        case .high: .moderate
        case .moderate: .low
        case .low: .low
        }
    }
}

/// The latest time the user can safely wake and still be ready for their earliest relevant event
/// (WG-145). Transparent: `latestSafeWake == bindingEventStart − leadTime`, recomputable from the inputs.
/// Carries its **uncertainty** and whether the events **conflict**.
struct LatestSafeWakePlan: Sendable, Equatable, Hashable {
    /// The latest instant to wake — may be in the past if an event is very soon (meaning "you'd need to be
    /// up already").
    let latestSafeWake: Date
    /// The start of the event that determined the wake time.
    let bindingEventStart: Date
    /// Whether a **user-confirmed** important event drove the plan (vs an inferred first event).
    let drivenByConfirmedImportant: Bool
    /// The lead time applied to the binding event (prep + safety, + travel if it had a location).
    let appliedLeadTime: TimeInterval
    /// Whether the binding event had a location (so the travel buffer was included) — lets the UI show the
    /// buffer breakdown (WG-146).
    let bindingHasLocation: Bool
    let confidence: WakePlanConfidence
    /// How many timed events were considered.
    let consideredEventCount: Int
    /// Whether any two considered events overlap in time.
    let hasConflicts: Bool
}

/// Computes the latest safe wake time from upcoming events + the morning-preparation profile (WG-145).
/// **Pure** — a deterministic function of the (redacted, coarse) events, the profile, and `now`. All-day
/// events are excluded (they don't drive a wake time); a user-confirmed critical event is a **hard**
/// deadline, else the earliest timed event is an inferred (lower-confidence) one; conflicting events are
/// handled (the earliest deadline wins, and the conflict lowers confidence). Returns `nil` when there is
/// no timed event to plan around — unavailable, never a fabricated time.
enum LatestSafeWakeCalculator {
    static func plan(
        for events: [RedactedEventSummary], profile: MorningPreparationProfile, after now: Date
    ) -> LatestSafeWakePlan? {
        // Only future, timed events can drive a wake time (all-day events are excluded).
        let timed = events.filter { !$0.isAllDay && $0.start > now }
        guard !timed.isEmpty else { return nil }

        func deadline(_ event: RedactedEventSummary) -> Date {
            event.start.addingTimeInterval(
                -profile.leadTime(forEventWithLocation: event.hasLocation))
        }

        let critical = timed.filter(\.isConfirmedImportant)
        let drivers = critical.isEmpty ? timed : critical
        // The binding event is the one you must be ready for **earliest** (the smallest deadline).
        guard let binding = drivers.min(by: { deadline($0) < deadline($1) }) else { return nil }

        let hasConflicts = conflicts(among: timed)
        var confidence: WakePlanConfidence = critical.isEmpty ? .moderate : .high
        if hasConflicts { confidence = confidence.downgraded }

        return LatestSafeWakePlan(
            latestSafeWake: deadline(binding),
            bindingEventStart: binding.start,
            drivenByConfirmedImportant: !critical.isEmpty,
            appliedLeadTime: profile.leadTime(forEventWithLocation: binding.hasLocation),
            bindingHasLocation: binding.hasLocation,
            confidence: confidence,
            consideredEventCount: timed.count,
            hasConflicts: hasConflicts)
    }

    /// Whether any two events overlap in time. Sorting by start makes this an adjacent check: if any event
    /// overlaps a later one, it overlaps its immediate successor, so a single pass suffices.
    private static func conflicts(among events: [RedactedEventSummary]) -> Bool {
        let sorted = events.sorted { $0.start < $1.start }
        guard sorted.count >= 2 else { return false }
        for index in 1..<sorted.count where sorted[index].start < sorted[index - 1].end {
            return true
        }
        return false
    }
}
