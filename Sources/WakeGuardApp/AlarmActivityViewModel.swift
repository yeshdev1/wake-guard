import Foundation
import Observation

/// Drives the "Alarm Activity" section (WG-299): loads the recent wakes (each with its **cached**
/// plain-English summary) and a **full summary** of them. The summary shows the deterministic aggregate
/// instantly, then upgrades in place to the on-device AI phrasing when it's ready — never blocking, and
/// falling back to the deterministic text if the model is unavailable (#33). Read-only: it holds no alarm
/// authority and reads on-device data only (#8/#35).
@MainActor
@Observable
final class AlarmActivityViewModel {
    private(set) var entries: [AlarmActivityEntry] = []
    private(set) var summary = ""
    private(set) var hasLoaded = false

    private let store: any AlarmActivityStore
    private let narrator: AlarmActivityNarrator
    private let limit: Int

    init(store: any AlarmActivityStore, narrator: AlarmActivityNarrator, limit: Int = 30) {
        self.store = store
        self.narrator = narrator
        self.limit = limit
    }

    /// Load the recent wakes and their summary. The per-card text is already cached in each entry; the
    /// full summary is recomputed here (the "from time to time" refresh — once per visit).
    func load() async {
        let loaded = await store.recentActivities(limit: limit)
        entries = loaded
        let activities = loaded.map(\.activity)
        summary = AlarmActivitySummary(activities).plainSummary  // instant, deterministic
        hasLoaded = true
        summary = await narrator.summarize(activities)  // upgrade to AI phrasing (or same fallback)
    }
}
