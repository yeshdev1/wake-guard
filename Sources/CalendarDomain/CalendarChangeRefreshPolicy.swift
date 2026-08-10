import Foundation

/// The rules for refreshing the tomorrow plan when the calendar changes (WG-147). Pure. A change bumps a
/// generation, so a proposal computed at an older generation is **stale** (never shown/applied); refreshes
/// are **rate-limited** so a burst of change notifications can't spam prompts. It performs no alarm
/// mutation — refreshing only recomputes an **advisory** recommendation.
struct CalendarChangeRefreshPolicy: Sendable {
    /// The minimum time between refreshes — bounds how often the recommendation (and any prompt) updates.
    let minimumRefreshInterval: TimeInterval

    static let defaultInterval: TimeInterval = 60

    init(minimumRefreshInterval: TimeInterval = defaultInterval) {
        self.minimumRefreshInterval =
            minimumRefreshInterval.isFinite ? max(minimumRefreshInterval, 0) : Self.defaultInterval
    }

    /// Whether a proposal computed at `proposalGeneration` is stale given the current `changeGeneration`.
    func isProposalStale(proposalGeneration: Int, changeGeneration: Int) -> Bool {
        proposalGeneration < changeGeneration
    }

    /// Whether a refresh is allowed now — only once `minimumRefreshInterval` has elapsed since the last
    /// one (coalescing a burst). A change that is throttled leaves the proposal **stale** until a refresh
    /// is allowed, so the UI never treats a stale recommendation as current.
    func shouldRefresh(now: Date, lastRefreshedAt: Date?) -> Bool {
        guard let lastRefreshedAt else { return true }
        return now.timeIntervalSince(lastRefreshedAt) >= minimumRefreshInterval
    }
}
