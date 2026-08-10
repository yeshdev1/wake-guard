import Foundation
import Observation

/// Keeps the tomorrow-plan recommendation fresh across calendar changes (WG-147). A calendar change
/// **invalidates** the current proposal (marks it stale, so a stale recommendation is never shown as
/// current), and refreshes are **throttled** (`CalendarChangeRefreshPolicy`) so a burst of change
/// notifications can't spam prompts. Refreshing only recomputes the **advisory** recommendation via the
/// injected `recompute` closure — this type holds **no alarm dependency**, so a calendar change can never
/// trigger an automatic (critical) alarm mutation. `@MainActor` because it feeds SwiftUI directly.
@MainActor
@Observable
final class TomorrowPlanRefresher {
    private(set) var presentation: TomorrowPlanPresentation?
    /// Whether the current recommendation is stale (a calendar change arrived and a refresh hasn't run).
    private(set) var isStale = false

    private var changeGeneration = 0
    private var proposalGeneration = -1
    private var lastRefreshedAt: Date?

    private let policy: CalendarChangeRefreshPolicy
    private let recompute: () async -> TomorrowPlanPresentation

    init(
        policy: CalendarChangeRefreshPolicy = CalendarChangeRefreshPolicy(),
        recompute: @escaping () async -> TomorrowPlanPresentation
    ) {
        self.policy = policy
        self.recompute = recompute
    }

    /// A calendar change arrived — invalidate the current proposal. **No alarm is touched.**
    func calendarChanged() {
        changeGeneration += 1
        isStale = policy.isProposalStale(
            proposalGeneration: proposalGeneration, changeGeneration: changeGeneration)
    }

    /// Recompute the recommendation **iff** the throttle allows (bounding prompt frequency). Recomputing
    /// only updates the advisory `presentation`; it never mutates an alarm. Returns whether it refreshed.
    @discardableResult
    func refreshIfNeeded(now: Date) async -> Bool {
        guard policy.shouldRefresh(now: now, lastRefreshedAt: lastRefreshedAt) else { return false }
        presentation = await recompute()
        proposalGeneration = changeGeneration
        isStale = false
        lastRefreshedAt = now
        return true
    }
}
