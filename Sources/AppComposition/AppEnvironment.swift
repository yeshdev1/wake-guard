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
    /// The consent-center status source (WG-180): reports each permission's live status, read-only —
    /// production reads the OS, the in-memory graph returns a fixed hermetic status. Holds no alarm
    /// authority (#9).
    let consentStatusProvider: any ConsentStatusProviding
    /// The deletion coordinator (WG-184): drives the deletion UI through the policy + `dataEraser`. A full
    /// reset is confirmation-gated; deleting optional data never touches alarms (#9).
    let deletionCoordinator: DeletionCoordinator
    /// The export data source (WG-183): gathers the user's local records (alarms, audit, settings) for the
    /// export flow. No network — the bundle goes to the system share sheet.
    let exportData: ExportDataProvider
    /// The device time-zone monitor (WG-100): started at launch in production, it reconciles alarms when the
    /// system zone changes — so a background zone change is corrected live, not only on the next foreground.
    /// Advisory (holds no alarm authority); the in-memory graph composes it but never starts it (hermetic).
    let timeZoneMonitor: SystemTimeZoneMonitor
    /// The operational diagnostics provider (WG-230): a read-only snapshot of permission statuses, the last
    /// reconcile result, the last safe schedule sync, and redacted recent errors — support-visible, no
    /// sensitive raw data. Fed by the reconcile-recording processor.
    let diagnosticsProvider: any DiagnosticsProviding
    /// The live pedometer source for the walk challenge (WG-073): the challenge runtime consumes it to drive
    /// the anti-shake machine. Production uses the real CoreMotion adapter; the in-memory graph reports it
    /// unavailable (so the challenge offers the accessible alternative, #21/#22). Holds no alarm authority.
    let pedometerLiveSource: any PedometerSource
    /// The on-device language model for conversational alarm creation (WG-160/166). Production uses
    /// FoundationModels; the in-memory graph reports it unavailable (the flow fails closed to the manual
    /// editor, #33). It only produces text — no tools, no alarm authority (#1/#30).
    let languageModelProvider: any LanguageModelProvider
    /// The guided-generation alarm parser (WG-301): the describe flow tries this first for a
    /// schema-constrained parse (#26), falling back to `languageModelProvider` when it's absent. `nil` in
    /// the in-memory graph, so tests/previews use the text fallback. Read-only; no alarm authority (#1/#30).
    let guidedAlarmParser: (any GuidedAlarmParsing)?
    /// Reports on-device-model availability (WG-162/300): the creation header reads it to show the honest
    /// "turn on Apple Intelligence" hint when it's off-but-supported. Read-only; no alarm authority (#9).
    let modelAvailabilityProvider: any ModelAvailabilityProviding
    /// Opens the system Settings app (WG-300) — used by the AI hint's "Open Settings" action. Production
    /// opens the app's Settings page; the in-memory graph no-ops (hermetic).
    let settingsOpener: any SettingsOpener
    /// The on-device wake-activity history (WG-299): the store the "Alarm Activity" section reads, and the
    /// recorder the challenge runtime writes to at each outcome. On-device only (#35/#40); advisory — it
    /// holds no alarm authority and its failure never affects an alarm (#8/#9).
    let alarmActivityStore: any AlarmActivityStore
    let alarmActivityRecorder: any AlarmActivityRecording
    /// The sleep-sample source for the readiness card (WG-121). Production reads HealthKit; the in-memory
    /// graph returns no samples (readiness degrades to "not enough data", #36/#38). Read-only, on device,
    /// never stored raw (#41); holds no alarm authority.
    let sleepQuery: any SleepSampleQuerying
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
        let clock = SystemClock()
        // The real AlarmKit adapter (so alarms ring) + the real Settings opener (denial recovery),
        // and schedulesAlarmsInSystem: true — the list surfaces the authorization banner until
        // permission is granted, never a false "it rings" (runs-on-a-phone steps 2–3).
        return make(
            persistence: persistence, clock: clock,
            identifierGenerator: SystemIdentifierGenerator(),
            wiring: SystemWiring(
                alarmManager: SystemAlarmManagerAdapter(), settingsOpener: UIKitSettingsOpener(),
                schedulesAlarmsInSystem: true,
                preAlarmNotifications: SystemPreAlarmNotificationScheduler(),
                travelNotifier: SystemTravelUpdateNotifier(),
                pedometerSource: CoreMotionHistoricalPedometerAdapter(),
                pedometerLiveSource: CoreMotionLivePedometerAdapter(),
                languageModelProvider: FoundationModelsLanguageModelProvider(),
                guidedAlarmParser: FoundationModelsGuidedAlarmParser(),
                modelAvailabilityProvider: FoundationModelsAvailabilityAdapter(),
                sleepQuery: HealthKitSleepQueryAdapter(),
                cloudTokenStore: KeychainCloudTokenStore(),
                makeConsentProvider: { alarm, settings, cloudToken in
                    // The location source's `authorizationStatus()` returns the domain enum, so the
                    // consent provider reads location consent without importing CoreLocation (#41).
                    SystemConsentStatusProvider(
                        alarm: alarm, settings: settings, cloudToken: cloudToken,
                        location: CoreLocationSignificantLocationAdapter(now: { clock.now }))
                }))
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
                travelNotifier: NoopTravelUpdateNotifier(),
                pedometerSource: UnavailablePedometerSource(),
                pedometerLiveSource: UnavailableLivePedometerSource(),
                languageModelProvider: UnavailableLanguageModelProvider(),
                guidedAlarmParser: nil,
                modelAvailabilityProvider: FixedModelAvailabilityProvider(),
                sleepQuery: UnavailableSleepQuery(),
                cloudTokenStore: InMemoryCloudTokenStore(),
                makeConsentProvider: { _, _, _ in FixedConsentStatusProvider() }))
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
        let travelNotifier: any TravelUpdateNotifying
        let pedometerSource: any HistoricalPedometerSource
        let pedometerLiveSource: any PedometerSource
        let languageModelProvider: any LanguageModelProvider
        let guidedAlarmParser: (any GuidedAlarmParsing)?
        let modelAvailabilityProvider: any ModelAvailabilityProviding
        let sleepQuery: any SleepSampleQuerying
        let cloudTokenStore: any CloudTokenStore
        /// Builds the consent provider from the in-`make` settings/token: production reads the OS, the
        /// in-memory graph returns a hermetic fixed status (so tests/previews never touch a framework).
        let makeConsentProvider:
            @Sendable (any AlarmManagerAdapter, any SettingsRepository, any CloudTokenStore) ->
                any ConsentStatusProviding
    }

    /// The privacy-control services (WG-250/180/183): the eraser, retention job, consent provider,
    /// deletion coordinator, and export gatherer — grouped so `make` stays within its budget.
    private struct PrivacyControls {
        let dataEraser: any DataEraser
        let retentionCleanup: RetentionCleanupJob
        let consentStatusProvider: any ConsentStatusProviding
        let deletionCoordinator: DeletionCoordinator
        let exportData: ExportDataProvider
    }

    private static func makePrivacyControls(
        persistence: PersistenceController, clock: any WallClock, wiring: SystemWiring
    ) -> PrivacyControls {
        // Fresh repositories over the same persistence controller — the Core Data repos are thin,
        // per-operation wrappers with no shared mutable state, so these read/write the identical store.
        let alarms = CoreDataAlarmRepository(persistence)
        let settings = CoreDataSettingsRepository(persistence)
        let eraser = CoreDataDataEraser(
            persistence: persistence, alarms: alarms, alarmManager: wiring.alarmManager,
            cloudToken: wiring.cloudTokenStore)
        return PrivacyControls(
            dataEraser: eraser,
            retentionCleanup: RetentionCleanupJob(
                persistence: persistence, alarms: alarms, clock: clock),
            consentStatusProvider: wiring.makeConsentProvider(
                wiring.alarmManager, settings, wiring.cloudTokenStore),
            deletionCoordinator: DeletionCoordinator(eraser: eraser),
            exportData: ExportDataProvider(
                persistence: persistence, alarms: alarms, settings: settings))
    }

    /// Build the command processor + its policy engine + the satisfied-wake store (WG-290) — extracted so
    /// `make()` stays within budget. The repos built here are thin per-op wrappers over the same
    /// controller, so they share state with the ones `make()` exposes (the established helper pattern).
    private static func makeCommandProcessor(
        persistence: PersistenceController, clock: any WallClock,
        ids: any IdentifierGenerator, wiring: SystemWiring
    ) -> AlarmCommandProcessor {
        let alarms = CoreDataAlarmRepository(persistence)
        // The satisfied-wake store: the processor records a genuine pass; the policy engine's
        // commitment-lock failsafe reads it, so a completed walk releases the ring-window lock.
        let satisfiedWakes = CoreDataSatisfiedWakeStore(persistence, now: { clock.now })
        let policy = DefaultAlarmPolicyEngine(
            alarms: alarms, clock: clock,
            isWakeSatisfied: { id, fire in
                await satisfiedWakes.isSatisfied(alarmID: id, fireTime: fire)
            })
        return AlarmCommandProcessor(
            policy: policy, alarms: alarms, audit: CoreDataAuditRepository(persistence),
            outbox: CoreDataOutboxRepository(persistence), alarmManager: wiring.alarmManager,
            clock: clock, ids: ids, satisfiedWakes: satisfiedWakes)
    }

    /// Build the wake-activity store + its on-device narrating recorder (WG-299) — extracted so `make()`
    /// stays within budget. On-device only; the narration is grounded (#32) and its prompt never logged.
    private static func makeActivityRecording(
        persistence: PersistenceController, wiring: SystemWiring
    ) -> (store: CoreDataAlarmActivityStore, recorder: DefaultAlarmActivityRecorder) {
        let store = CoreDataAlarmActivityStore(persistence)
        let recorder = DefaultAlarmActivityRecorder(
            narrator: AlarmActivityNarrator(
                generator: ExplanationGenerator(
                    generator: StructuredGenerator(provider: wiring.languageModelProvider))),
            store: store)
        return (store, recorder)
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
        let processor = makeCommandProcessor(
            persistence: persistence, clock: clock, ids: identifierGenerator, wiring: wiring)
        // Wrap the processor so every reconcile() records into the store the diagnostics provider reads.
        let (recorder, reconcileStore) = makeRecordingProcessor(wrapping: processor, clock: clock)
        let promptCoordinator = PreAlarmPromptCoordinator(
            ledger: CoreDataPreAlarmPromptLedger(persistence))
        let authorizationCoordinator = AlarmAuthorizationCoordinator(
            adapter: wiring.alarmManager, settingsOpener: wiring.settingsOpener)
        let preAlarmResponder = PreAlarmNotificationResponder(
            processor: recorder, notifications: wiring.preAlarmNotifications)
        let preAlarmWork = PreAlarmBackgroundWork(
            alarms: alarms,
            pipeline: PreAlarmPipeline(
                movementQuery: RecentMovementQuery(source: wiring.pedometerSource),
                coordinator: promptCoordinator),
            notifications: wiring.preAlarmNotifications, deviceTimeZone: { .current })
        let preAlarmFeedback = CoreDataPreAlarmFeedbackStore(persistence)
        let activity = makeActivityRecording(persistence: persistence, wiring: wiring)
        let privacy = makePrivacyControls(persistence: persistence, clock: clock, wiring: wiring)
        return AppEnvironment(
            clock: clock,
            identifierGenerator: identifierGenerator,
            alarmRepository: alarms,
            auditRepository: audit,
            outboxRepository: outbox,
            settingsRepository: settings,
            alarmCommandProcessor: recorder,
            preAlarmPromptCoordinator: promptCoordinator,
            authorizationCoordinator: authorizationCoordinator,
            preAlarmNotifications: wiring.preAlarmNotifications,
            preAlarmResponder: preAlarmResponder, preAlarmWork: preAlarmWork,
            preAlarmFeedback: preAlarmFeedback, cloudTokenStore: wiring.cloudTokenStore,
            dataEraser: privacy.dataEraser, retentionCleanup: privacy.retentionCleanup,
            consentStatusProvider: privacy.consentStatusProvider,
            deletionCoordinator: privacy.deletionCoordinator, exportData: privacy.exportData,
            timeZoneMonitor: makeTimeZoneMonitor(
                processor: recorder, notifier: wiring.travelNotifier),
            diagnosticsProvider: DefaultDiagnosticsProvider(
                consent: privacy.consentStatusProvider, reconcile: reconcileStore),
            pedometerLiveSource: wiring.pedometerLiveSource,
            languageModelProvider: wiring.languageModelProvider,
            guidedAlarmParser: wiring.guidedAlarmParser,
            modelAvailabilityProvider: wiring.modelAvailabilityProvider,
            settingsOpener: wiring.settingsOpener, alarmActivityStore: activity.store,
            alarmActivityRecorder: activity.recorder, sleepQuery: wiring.sleepQuery,
            schedulesAlarmsInSystem: wiring.schedulesAlarmsInSystem)
    }
}
