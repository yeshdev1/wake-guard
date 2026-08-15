import Foundation
import Observation

/// One alarm as shown in the list (WG-041) — derived from the domain `Alarm` and its next
/// occurrence, using the design system's status vocabulary.
struct AlarmListItem: Identifiable, Equatable, Sendable {
    let id: AlarmID
    let label: String
    let isEnabled: Bool
    let isCritical: Bool
    let status: AlarmStatusStyle
    /// The next fire instant, or nil when the alarm has none (disabled, or a past one-time).
    let nextOccurrence: Date?
    /// Localized next-ring text — relative day + time, honoring the 12/24-hour setting — or
    /// an off/none phrase.
    let nextRingText: String
    /// A single combined VoiceOver announcement: (criticality,) label, status, next ring.
    let accessibilityLabel: String
    /// The walk-challenge step target if this alarm requires a walk challenge, else `nil` — drives the
    /// "test the walk challenge" affordance (WG-073). Non-walk / no challenge is `nil`.
    let challengeRequiredSteps: Int?
}

/// The loaded content: the soonest upcoming alarm (the "next-alarm summary") and the full
/// list.
struct AlarmListContent: Equatable, Sendable {
    let nextAlarm: AlarmListItem?
    let items: [AlarmListItem]
}

/// The list's display state. `failed` is explicit and **distinct from `empty`** — a storage
/// failure must never render as "no alarms" (SAFETY_INVARIANTS #10; the WG-018
/// nil-environment contract). Reconciliation is a *separate* non-blocking flag
/// (`isReconciling`), not a state, so the last-known list stays visible while it runs.
enum AlarmListState: Equatable, Sendable {
    case loading
    case empty
    case loaded(AlarmListContent)
    case failed(reason: String)
}

/// Loads alarms for the list screen and maps them to display state. Read-only: it never
/// mutates an alarm (that is the command processor's job, #2) — it reads the repository and
/// computes next occurrences through the pure scheduling engine (the same call the processor
/// and reconciler use, so the displayed time can't disagree with what fires).
@MainActor
@Observable
final class AlarmListViewModel {
    private(set) var state: AlarmListState = .loading
    /// Whether launch/foreground reconciliation (WG-029) is in progress — shown as a
    /// non-blocking banner over the current list, never a blanking full-screen state. The
    /// trigger is wired with the reconcile follow-on; `setReconciling(_:)` is the seam.
    private(set) var isReconciling = false

    /// A row action awaiting confirmation because the policy engine required it — a critical
    /// or imminent destructive change (#6). The view shows `reason`; on confirm it re-submits.
    private(set) var pendingConfirmation: PendingConfirmation?
    /// A failed action's user-safe reason; the alarm is left unchanged (a clear safe state).
    private(set) var actionError: String?

    struct PendingConfirmation: Equatable, Sendable {
        let command: AlarmCommand
        let reason: String
    }

    private let alarms: any AlarmRepository
    private let clock: any WallClock
    /// The mutation boundary (WG-043). `nil` in read-only contexts (WG-041 tests / previews);
    /// the app always injects it, so row actions submit every change through the processor
    /// (never persistence or the adapter directly, #2/#3).
    private let processor: (any AlarmCommandProcessing)?
    private let deviceTimeZone: @Sendable () -> TimeZone
    private let engine = AlarmSchedulingEngine()
    /// Guards overlapping loads: only the latest-started load commits its result, so a slow
    /// earlier load can never clobber a fresher one (e.g. a foreground reload).
    private var loadGeneration = 0
    /// The loaded alarms by id, so the edit flow can hand the full `Alarm` to the form.
    private var alarmsByID: [AlarmID: Alarm] = [:]

    init(
        alarms: any AlarmRepository, clock: any WallClock,
        processor: (any AlarmCommandProcessing)? = nil,
        deviceTimeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.alarms = alarms
        self.clock = clock
        self.processor = processor
        self.deviceTimeZone = deviceTimeZone
    }

    /// Set by the reconcile trigger (WG-029) to show/hide the reconciling banner.
    func setReconciling(_ value: Bool) {
        isReconciling = value
    }

    /// Reconcile the system authority against saved alarms (WG-029), then refresh the list. Shows the
    /// non-blocking reconciling banner while it runs — the last-known list stays visible, never a
    /// blanking state. Safe on every launch/foreground: reconciliation is idempotent and fails safe
    /// (#10), and is opportunistic — never required for a critical alarm to ring (#9). A read-only
    /// context (no processor: WG-041 previews/tests) simply reloads.
    func reconcile() async {
        guard let processor else { return await load() }
        setReconciling(true)
        _ = await processor.reconcile()
        setReconciling(false)
        await load()
    }

    /// Re-reads the alarms and recomputes the list against the *current* time. Safe to call
    /// repeatedly (on appear and on every foreground) — only the latest call commits.
    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        // Only blank to the spinner on a COLD load (or a retry after failure). A refresh that already has
        // a resolved list keeps it on screen and swaps in place when the new data lands — otherwise every
        // foreground, reconcile, and sheet-dismiss reload flashed the whole list to "Loading…" and back,
        // which read as a glitch (and briefly exposed a dismissing sheet's title over the re-layout). This
        // is the "last-known list stays visible, never a blanking state" guarantee `reconcile()` promises.
        if Self.showsLoadingSpinner(whileRefreshing: state) { state = .loading }
        let all: [Alarm]
        do {
            all = try await alarms.allAlarms()
        } catch {
            guard generation == loadGeneration else { return }  // superseded by a newer load
            // Explicit failure — never fall through to `.empty`, which would falsely tell the
            // user they have no alarms when they are simply unreadable right now (#10).
            state = .failed(
                reason: "Your alarms couldn’t be loaded. They are still saved — reopen the app "
                    + "to try again.")
            return
        }
        guard generation == loadGeneration else { return }  // superseded by a newer load
        alarmsByID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        state = all.isEmpty ? .empty : .loaded(content(from: all))
    }

    /// Whether a starting load should show the blocking loading spinner. A refresh that already has a
    /// **resolved** list (`.loaded`/`.empty`) keeps it visible so the list never blanks/flashes (WG-297);
    /// a cold start (`.loading`) or a retry after a `.failed` load does show it. Pure — unit-tested.
    static func showsLoadingSpinner(whileRefreshing state: AlarmListState) -> Bool {
        switch state {
        case .loaded, .empty: false
        case .loading, .failed: true
        }
    }

    // MARK: - Row actions (every mutation routes through the command processor, #2/#3/#46)

    /// The full alarm behind a row, for the edit form.
    func alarm(for id: AlarmID) -> Alarm? { alarmsByID[id] }

    /// Enable or disable an alarm. Disabling a critical / imminent one needs confirmation (#6).
    func setEnabled(_ enabled: Bool, for id: AlarmID) async {
        await submit(enabled ? .enable(id) : .disable(id))
    }

    /// Delete an alarm. Deleting a critical / imminent one needs confirmation (#6).
    func delete(_ id: AlarmID) async {
        await submit(.delete(id))
    }

    /// Re-submit the pending action with the user's explicit confirmation (#6).
    func confirmPending() async {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        await submit(pending.command, confirmed: true)
    }

    func cancelPendingConfirmation() async {
        pendingConfirmation = nil
        await load()  // restore the true state (e.g. an optimistic toggle that didn't apply)
    }

    func dismissActionError() { actionError = nil }

    private func submit(_ command: AlarmCommand, confirmed: Bool = false) async {
        guard let processor else { return }
        switch await processor.process(
            command, from: .userInterface, by: .user, userConfirmed: confirmed)
        {
        case .needsConfirmation(let reason):
            // The policy withheld a destructive change to a critical / imminent alarm (#6) —
            // ask the user. Reload first so an optimistic control (e.g. a toggle the user just
            // flipped) snaps back to the alarm's true, still-unchanged state under the prompt.
            await load()
            pendingConfirmation = PendingConfirmation(command: command, reason: reason)
        case .applied, .uncertain, .noOp:
            await load()
        case .rejected(let reason), .failed(let reason), .unsupported(let reason):
            // Not confirmable (a fail-closed error, an unsupported command): the alarm is
            // unchanged; show the reason and reflect its true state (#10). Never a prompt.
            actionError = reason
            await load()
        }
    }

    private func content(from alarms: [Alarm]) -> AlarmListContent {
        let now = clock.now
        let zone = deviceTimeZone()
        var calendar = Calendar.current
        calendar.timeZone = zone
        let items =
            alarms
            .map { item(from: $0, now: now, zone: zone, calendar: calendar) }
            .sorted(by: Self.ordering)
        let nextAlarm =
            items
            .filter { $0.nextOccurrence != nil }
            .min { ($0.nextOccurrence ?? .distantFuture) < ($1.nextOccurrence ?? .distantFuture) }
        return AlarmListContent(nextAlarm: nextAlarm, items: items)
    }

    private func item(from alarm: Alarm, now: Date, zone: TimeZone, calendar: Calendar)
        -> AlarmListItem
    {
        let occurrence =
            alarm.isEnabled
            ? engine.nextOccurrence(for: alarm, after: now, deviceTimeZone: zone) : nil
        let status = Self.status(for: alarm, hasOccurrence: occurrence != nil)
        let ringText = Self.nextRingText(
            occurrence: occurrence, isEnabled: alarm.isEnabled, now: now, zone: zone,
            calendar: calendar)
        let label = alarm.label.isEmpty ? "Alarm" : alarm.label
        let isCritical = alarm.criticality == .critical
        let challengeSteps: Int? = {
            if case .walk(let walk) = alarm.challengePolicy { return walk.minimumSteps }
            return nil
        }()
        return AlarmListItem(
            id: alarm.id, label: label, isEnabled: alarm.isEnabled, isCritical: isCritical,
            status: status, nextOccurrence: occurrence, nextRingText: ringText,
            accessibilityLabel: Self.accessibilityLabel(
                label: label, status: status, ringText: ringText, isEnabled: alarm.isEnabled,
                isCritical: isCritical),
            challengeRequiredSteps: challengeSteps)
    }

    private static func accessibilityLabel(
        label: String, status: AlarmStatusStyle, ringText: String, isEnabled: Bool, isCritical: Bool
    ) -> String {
        // Lead with criticality so VoiceOver announces the most safety-important fact first.
        let prefix = isCritical ? "Critical alarm. " : ""
        // A disabled alarm's status ("Off") already implies no ring — don't repeat "Off".
        guard isEnabled else { return "\(prefix)\(label), \(status.label)" }
        return "\(prefix)\(label), \(status.label), \(ringText)"
    }

    private static func status(for alarm: Alarm, hasOccurrence: Bool) -> AlarmStatusStyle {
        guard alarm.isEnabled else { return .off }
        // An enabled alarm with nothing upcoming (e.g. a past one-time alarm) can't ring — surface it as
        // needing attention **even if it's marked critical** (WG-241), rather than a reassuring "Critical"
        // that hides the fact it won't fire.
        guard hasOccurrence else { return .attention }
        return alarm.criticality == .critical ? .critical : .scheduled
    }

    private static func nextRingText(
        occurrence: Date?, isEnabled: Bool, now: Date, zone: TimeZone, calendar: Calendar
    ) -> String {
        guard isEnabled else { return "Off" }
        guard let occurrence else { return "No upcoming time" }
        var timeStyle = Date.FormatStyle(time: .shortened)
        timeStyle.timeZone = zone
        let day = dayLabel(occurrence, now: now, zone: zone, calendar: calendar)
        return "\(day), \(occurrence.formatted(timeStyle))"
    }

    /// A glanceable day label: Today / Tomorrow / a weekday within a week / an abbreviated
    /// date beyond that — far more scannable for an imminent alarm than an absolute datetime.
    private static func dayLabel(_ occurrence: Date, now: Date, zone: TimeZone, calendar: Calendar)
        -> String
    {
        if calendar.isDate(occurrence, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
            calendar.isDate(occurrence, inSameDayAs: tomorrow)
        {
            return "Tomorrow"
        }
        if let weekAhead = calendar.date(byAdding: .day, value: 7, to: now), occurrence < weekAhead
        {
            var weekday = Date.FormatStyle().weekday(.wide)
            weekday.timeZone = zone
            return occurrence.formatted(weekday)
        }
        var dateStyle = Date.FormatStyle(date: .abbreviated)
        dateStyle.timeZone = zone
        return occurrence.formatted(dateStyle)
    }

    /// Upcoming-soonest first; alarms with no next fire last; ties broken by label.
    private static func ordering(_ lhs: AlarmListItem, _ rhs: AlarmListItem) -> Bool {
        switch (lhs.nextOccurrence, rhs.nextOccurrence) {
        case let (left?, right?): return left < right
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil):
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }
}
