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
    /// The AlarmKit authorization coordinator (WG-025): drives the permission explanation + system
    /// prompt behind the alarm-list banner. Read-only with respect to alarms — a denial never drops a
    /// scheduled alarm (#10); wired to the same adapter that schedules, so auth and scheduling agree.
    let authorizationCoordinator: AlarmAuthorizationCoordinator
    /// The pre-alarm notification surface (runs-on-a-phone step 5): registers the prompt category and
    /// posts / cancels the advisory prompt (production uses `SystemPreAlarmNotificationScheduler`; the
    /// in-memory graph a no-op). Holds no alarm authority (#7/#8).
    let preAlarmNotifications: any PreAlarmNotificationScheduling
    /// Executes a tapped pre-alarm notification action (runs-on-a-phone step 5): routes it to a decision
    /// and submits the resulting command through the processor (a critical/imminent turn-off is
    /// confirmation-gated, #6). The app's `UNUserNotificationCenterDelegate` forwards to this.
    let preAlarmResponder: PreAlarmNotificationResponder
    /// The pre-alarm evaluation work (runs-on-a-phone step 6): the foreground-fallback / background
    /// opportunity that evaluates upcoming alarms and posts the advisory prompt. Holds no alarm
    /// authority (#7/#8/#9); production drives it with the real Core Motion pipeline, the in-memory
    /// graph with an unavailable source (so it never posts).
    let preAlarmWork: PreAlarmBackgroundWork
    /// The false-positive feedback store (WG-090): records the user's coarse "I wasn't awake" / "helpful"
    /// feedback on the pre-alarm. Aggregate + on-device; holds no alarm authority and cannot retune any
    /// behavior (#8/#31/#41) — advisory only.
    let preAlarmFeedback: any PreAlarmFeedbackStore
    /// The optional cloud-AI token store (WG-185): Keychain-backed in production, in-memory for
    /// tests/previews. Exposed so the consent center + full-reset erase can revoke it (#35).
    let cloudTokenStore: any CloudTokenStore
    /// The production data eraser (WG-250): the full-reset + optional-category deletion runs over the real
    /// stores through this. A full reset cancels scheduled alarms and clears every store; deleting optional
    /// data never touches alarms (#9). The deletion UI drives it via `DeletionCoordinator`.
    let dataEraser: any DataEraser
    /// The retention cleanup job (WG-250/182): a launch/foreground best-effort caller of `RetentionCleanup`
    /// that prunes audit rows past their window, bounded by the 365-day critical-audit floor (#48). Never
    /// required (#9).
    let retentionCleanup: RetentionCleanupJob
    /// Whether this build places alarms in the system authority. `true` in production (the real
    /// `SystemAlarmManagerAdapter`); `false` for the in-memory (test/preview) graph, which composes
    /// the interim `DeferredAlarmManagerAdapter` and shows a "won't ring here" banner. When `true` the
    /// list surfaces the authorization banner until permission is granted — so a saved alarm is never
    /// falsely implied to ring (#7).
    let schedulesAlarmsInSystem: Bool

    /// The production graph: durable on-disk Core Data and the live wall clock and
    /// UUID generator. Throws if the persistent store cannot load (storage
    /// unavailable) — the app surfaces that rather than running without persistence.
    static func production() throws -> AppEnvironment {
        let persistence = try PersistenceController(inMemory: false)
        // The real AlarmKit adapter (so alarms ring) + the real Settings opener (denial recovery),
        // and schedulesAlarmsInSystem: true — the list surfaces the authorization banner until
        // permission is granted, never a false "it rings" (runs-on-a-phone steps 2–3).
        return make(
            persistence: persistence, clock: SystemClock(),
            identifierGenerator: SystemIdentifierGenerator(),
            wiring: SystemWiring(
                alarmManager: SystemAlarmManagerAdapter(), settingsOpener: UIKitSettingsOpener(),
                schedulesAlarmsInSystem: true,
                preAlarmNotifications: SystemPreAlarmNotificationScheduler(),
                pedometerSource: CoreMotionHistoricalPedometerAdapter(),
                cloudTokenStore: KeychainCloudTokenStore()))
    }

    /// The test/preview graph: an ephemeral in-memory store, with the clock and id
    /// generator injectable so deterministic tests can fix time and ids. Previews use
    /// the live defaults — the *store* is the fake (nothing touches disk).
    static func inMemory(
        clock: any WallClock = SystemClock(),
        identifierGenerator: any IdentifierGenerator = SystemIdentifierGenerator()
    ) throws -> AppEnvironment {
        let persistence = try PersistenceController(inMemory: true)
        // Tests/previews never touch AlarmKit or a system navigation — the interim deferred adapter
        // + a no-op Settings opener keep them hermetic and crash-free (schedulesAlarmsInSystem: false).
        return make(
            persistence: persistence, clock: clock,
            identifierGenerator: identifierGenerator,
            wiring: SystemWiring(
                alarmManager: DeferredAlarmManagerAdapter(), settingsOpener: NoopSettingsOpener(),
                schedulesAlarmsInSystem: false,
                preAlarmNotifications: NoopPreAlarmNotificationScheduler(),
                pedometerSource: UnavailablePedometerSource(),
                cloudTokenStore: InMemoryCloudTokenStore()))
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

    /// Wires one persistence stack into all four repositories (so they share a store) and composes
    /// the command processor + the authorization coordinator over the **same** injected
    /// `AlarmManagerAdapter` — so authorization and scheduling always agree. `production()` passes the
    /// real `SystemAlarmManagerAdapter`; `inMemory()` passes the interim `DeferredAlarmManagerAdapter`
    /// so tests/previews never touch AlarmKit (runs-on-a-phone steps 2–3).
    /// The system-integration wiring the two graphs differ on: which alarm authority + Settings opener
    /// are composed, and whether this build places alarms in the system (drives the list disclosure).
    /// Bundled so `make` stays within one responsibility (and the parameter budget).
    private struct SystemWiring {
        let alarmManager: any AlarmManagerAdapter
        let settingsOpener: any SettingsOpener
        let schedulesAlarmsInSystem: Bool
        let preAlarmNotifications: any PreAlarmNotificationScheduling
        let pedometerSource: any HistoricalPedometerSource
        let cloudTokenStore: any CloudTokenStore
    }

    private static func make(
        persistence: PersistenceController,
        clock: any WallClock,
        identifierGenerator: any IdentifierGenerator,
        wiring: SystemWiring
    ) -> AppEnvironment {
        let alarms = CoreDataAlarmRepository(persistence)
        let audit = CoreDataAuditRepository(persistence)
        let outbox = CoreDataOutboxRepository(persistence)
        let settings = CoreDataSettingsRepository(persistence)
        let policy = DefaultAlarmPolicyEngine(alarms: alarms, clock: clock)
        let processor = AlarmCommandProcessor(
            policy: policy, alarms: alarms, audit: audit, outbox: outbox,
            alarmManager: wiring.alarmManager, clock: clock, ids: identifierGenerator)
        let promptCoordinator = PreAlarmPromptCoordinator(
            ledger: CoreDataPreAlarmPromptLedger(persistence))
        let authorizationCoordinator = AlarmAuthorizationCoordinator(
            adapter: wiring.alarmManager, settingsOpener: wiring.settingsOpener)
        let preAlarmResponder = PreAlarmNotificationResponder(
            processor: processor, notifications: wiring.preAlarmNotifications)
        let preAlarmWork = PreAlarmBackgroundWork(
            alarms: alarms,
            pipeline: PreAlarmPipeline(
                movementQuery: RecentMovementQuery(source: wiring.pedometerSource),
                coordinator: promptCoordinator),
            notifications: wiring.preAlarmNotifications, deviceTimeZone: { .current })
        let preAlarmFeedback = CoreDataPreAlarmFeedbackStore(persistence)
        let dataEraser = CoreDataDataEraser(
            persistence: persistence, alarms: alarms, alarmManager: wiring.alarmManager,
            cloudToken: wiring.cloudTokenStore)
        let retentionCleanup = RetentionCleanupJob(
            persistence: persistence, audit: audit, alarms: alarms, clock: clock)
        return AppEnvironment(
            clock: clock,
            identifierGenerator: identifierGenerator,
            alarmRepository: alarms,
            auditRepository: audit,
            outboxRepository: outbox,
            settingsRepository: settings,
            alarmCommandProcessor: processor,
            preAlarmPromptCoordinator: promptCoordinator,
            authorizationCoordinator: authorizationCoordinator,
            preAlarmNotifications: wiring.preAlarmNotifications,
            preAlarmResponder: preAlarmResponder,
            preAlarmWork: preAlarmWork,
            preAlarmFeedback: preAlarmFeedback,
            cloudTokenStore: wiring.cloudTokenStore,
            dataEraser: dataEraser,
            retentionCleanup: retentionCleanup,
            schedulesAlarmsInSystem: wiring.schedulesAlarmsInSystem)
    }
}
