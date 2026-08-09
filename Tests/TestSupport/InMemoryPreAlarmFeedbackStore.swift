import Foundation

@testable import WakeGuard

/// An in-memory `PreAlarmFeedbackStore` for tests (WG-090): a coarse `PreAlarmFeedbackCounts` tally
/// folded in memory. An `actor`, so the read-modify-write is race-free like the persisted store. Holds
/// no alarm authority — it only tallies coarse feedback categories.
actor InMemoryPreAlarmFeedbackStore: PreAlarmFeedbackStore {
    private var tally: PreAlarmFeedbackCounts = .empty

    func record(_ category: PreAlarmFeedbackCategory) async {
        tally = tally.recording(category)
    }

    func counts() async -> PreAlarmFeedbackCounts {
        tally
    }
}
