import Foundation

/// The composed application dependency graph (WG-018) — the single place the
/// concrete implementation of every port is chosen and wired together.
///
/// It is a plain value passed by injection (constructor / SwiftUI environment),
/// **not a service locator**: there is deliberately no global or `shared` instance,
/// and domain code never references this type — it receives the ports it needs
/// directly (ARCHITECTURE §1/§5; ADR-003 boundary discipline, enforced by the
/// `domain_no_composition_root` lint rule).
///
/// Two explicit graphs — `production()` (on-disk Core Data + live clock/ids) and
/// `inMemory(...)` (ephemeral Core Data + injectable clock/ids for tests and
/// previews) — each list every dependency in one place, so the wiring is reviewable.
struct AppEnvironment: Sendable {
    let clock: any WallClock
    let identifierGenerator: any IdentifierGenerator
    let alarmRepository: any AlarmRepository
    let auditRepository: any AuditRepository
    let outboxRepository: any OutboxRepository
    let settingsRepository: any SettingsRepository
    /// The single alarm-mutation boundary (WG-042): the create/edit/enable/disable flows
    /// submit commands here, applied by `AlarmCommandProcessor` — authorized (#3), audited
    /// (#46), and synced to the alarm authority. Screens never touch persistence or the
    /// adapter directly.
    let alarmCommandProcessor: any AlarmCommandProcessing
    /// The pre-alarm prompt de-dup (WG-089): the background opportunity (WG-088) and a foreground
    /// launch (WG-089) both route their evaluation's surface decision through this, so a prompt shows
    /// at most once per (alarm, occurrence). Persisted, so the de-dup survives relaunch. It holds no
    /// alarm authority — surfacing/suppressing a prompt never changes an alarm.
    let preAlarmPromptCoordinator: PreAlarmPromptCoordinator
    /// Whether created alarms are actually placed in the system authority yet. `false` while
    /// the interim `DeferredAlarmManagerAdapter` is composed (WG-042) — alarms are saved and
    /// shown but **do not ring** until the real `SystemAlarmManagerAdapter` + authorization UI
    /// land (WG-025 UI / WG-030). The UI discloses this so a saved alarm is never silently
    /// implied to ring.
    let schedulesAlarmsInSystem: Bool

    /// The production graph: durable on-disk Core Data and the live wall clock and
    /// UUID generator. Throws if the persistent store cannot load (storage
    /// unavailable) — the app surfaces that rather than running without persistence.
    static func production() throws -> AppEnvironment {
        let persistence = try PersistenceController(inMemory: false)
        return make(
            persistence: persistence, clock: SystemClock(),
            identifierGenerator: SystemIdentifierGenerator())
    }

    /// The test/preview graph: an ephemeral in-memory store, with the clock and id
    /// generator injectable so deterministic tests can fix time and ids. Previews use
    /// the live defaults — the *store* is the fake (nothing touches disk).
    static func inMemory(
        clock: any WallClock = SystemClock(),
        identifierGenerator: any IdentifierGenerator = SystemIdentifierGenerator()
    ) throws -> AppEnvironment {
        let persistence = try PersistenceController(inMemory: true)
        return make(
            persistence: persistence, clock: clock,
            identifierGenerator: identifierGenerator)
    }

    /// A non-throwing in-memory graph for SwiftUI previews (the store is the fake;
    /// nothing touches disk). Traps only if the in-memory store cannot load, which
    /// would indicate a broken managed-object model, not a runtime condition — so it
    /// is confined to preview code, never a production path.
    static var preview: AppEnvironment {
        do {
            return try inMemory()
        } catch {
            fatalError("in-memory preview composition failed: \(error)")
        }
    }

    /// Wires one persistence stack into all four repositories (so they share a store) and
    /// composes the command processor over them — the policy engine (WG-028) + the interim
    /// `DeferredAlarmManagerAdapter` (no AlarmKit yet; WG-042). Swapping in the real
    /// `SystemAlarmManagerAdapter` is the AlarmKit-integration follow-on (WG-025 UI / WG-030).
    private static func make(
        persistence: PersistenceController,
        clock: any WallClock,
        identifierGenerator: any IdentifierGenerator
    ) -> AppEnvironment {
        let alarms = CoreDataAlarmRepository(persistence)
        let audit = CoreDataAuditRepository(persistence)
        let outbox = CoreDataOutboxRepository(persistence)
        let settings = CoreDataSettingsRepository(persistence)
        let policy = DefaultAlarmPolicyEngine(alarms: alarms, clock: clock)
        let processor = AlarmCommandProcessor(
            policy: policy, alarms: alarms, audit: audit, outbox: outbox,
            alarmManager: DeferredAlarmManagerAdapter(), clock: clock, ids: identifierGenerator)
        let promptCoordinator = PreAlarmPromptCoordinator(
            ledger: CoreDataPreAlarmPromptLedger(persistence))
        return AppEnvironment(
            clock: clock,
            identifierGenerator: identifierGenerator,
            alarmRepository: alarms,
            auditRepository: audit,
            outboxRepository: outbox,
            settingsRepository: settings,
            alarmCommandProcessor: processor,
            preAlarmPromptCoordinator: promptCoordinator,
            // The interim adapter does not touch AlarmKit yet, so nothing rings — disclosed.
            schedulesAlarmsInSystem: false)
    }
}
