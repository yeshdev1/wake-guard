import Foundation

/// The production `DataEraser` (WG-250) — erases WakeGuard's local data over the real Core Data stores, the
/// scheduled system alarms, and the Keychain cloud token. This is the composition-root conformance the
/// deletion flow (`DeletionCoordinator`) runs on.
///
/// `eraseAllData()` is the confirmation-gated full reset: it cancels every scheduled alarm first (so none
/// rings after the reset), clears every Core Data entity, and revokes the cloud token. `eraseOptional(_:)`
/// erases only optional categories and never touches alarms (#9); none of the optional categories has a
/// persistent store today (derived motion, recommendations, journal, and health-derived data are
/// computed-and-discarded / never copied to disk, #35/#50), so there is nothing on disk to remove — see
/// the WG-250 ADR in `docs/DECISIONS.md`.
struct CoreDataDataEraser: DataEraser {
    let persistence: PersistenceController
    let alarms: any AlarmRepository
    let alarmManager: any AlarmManagerAdapter
    let cloudToken: any CloudTokenStore

    func eraseOptional(_ categories: Set<OptionalDataCategory>) async throws {
        // No optional category is persisted locally today, so this is intentionally a no-op that leaves
        // alarms untouched (#9). When a store is added for a category (e.g. a journal), erase it here.
        _ = categories
    }

    func eraseAllData() async throws {
        // Cancel scheduled system alarms first, so nothing rings after the reset. Best-effort per alarm: a
        // failed cancel leaves at most a stray system alarm (reconciliation reaps it) and never blocks the
        // erase — the local records are the source of truth and are cleared next.
        if let existing = try? await alarms.allAlarms() {
            for alarm in existing { try? await alarmManager.cancel(alarmID: alarm.id) }
        }
        try await persistence.eraseAllEntities()
        try? await cloudToken.revoke()
    }
}
