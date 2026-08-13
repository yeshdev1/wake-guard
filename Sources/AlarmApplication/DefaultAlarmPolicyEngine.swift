import Foundation

/// The default `AlarmPolicyEngine` (WG-028): the deterministic authorization authority
/// — the policy engine, not the model, decides (#3, #31). It evaluates **criticality,
/// actor (source), user confirmation, and time-to-fire**, and returns a
/// user-displayable deny reason.
///
/// Additive commands (create / enable) and system commands (reconcile / recover /
/// markChallengePassed) are always authorized — they add or preserve protection.
/// **Destructive** commands (cancel / delay / weaken) are gated: a critical — or
/// imminent — alarm cannot be cancelled, delayed, or weakened without explicit user
/// confirmation (#6), and an **automated proposal can never suppress a critical alarm**
/// (#4), so an AI cannot bypass this gate.
struct DefaultAlarmPolicyEngine: AlarmPolicyEngine {
    /// Destructive actions on an alarm firing within this window of `now` require
    /// confirmation, so a soon-to-fire alarm is not cancelled by accident (the
    /// time-to-fire factor). Tunable.
    static let imminentWindow: TimeInterval = 300

    private let alarms: any AlarmRepository
    private let clock: any WallClock
    private let deviceTimeZone: @Sendable () -> TimeZone
    /// The fire instant of an **unsatisfied** pending wake for this alarm, if one is being tracked —
    /// extends the commitment lock through the bounded ring window (WG-288). Defaults to "none" until the
    /// pending-wake store exists (WG-290), which wires the real read here.
    private let pendingUnsatisfiedFireTime: @Sendable (AlarmID) async -> Date?
    private let engine = AlarmSchedulingEngine()

    init(
        alarms: any AlarmRepository,
        clock: any WallClock,
        deviceTimeZone: @escaping @Sendable () -> TimeZone = { .current },
        pendingUnsatisfiedFireTime: @escaping @Sendable (AlarmID) async -> Date? = { _ in nil }
    ) {
        self.alarms = alarms
        self.clock = clock
        self.deviceTimeZone = deviceTimeZone
        self.pendingUnsatisfiedFireTime = pendingUnsatisfiedFireTime
    }

    func authorize(
        _ command: AlarmCommand, from source: CommandSource, userConfirmed: Bool
    ) async -> PolicyDecision {
        // #31: only the user (via the UI) assigns criticality — never a model. An automated
        // proposal that would create a critical alarm, or change an alarm's criticality, is
        // rejected outright; unlike #6 this is not confirmable (a model can't confirm, #4).
        if source == .agentProposal, let reason = await modelCriticalityChange(command) {
            return .rejected(reason: reason)
        }
        guard isDestructive(command) else {
            return .authorized  // additive / system commands add or preserve protection.
        }
        // Weigh the *current* alarm's criticality and time-to-fire. A *thrown* read
        // error is not "no such alarm": we cannot tell whether this is a critical
        // alarm, so fail **closed** — never authorize a destructive action we can't
        // weigh against #6/#4. Only a definite `nil` (genuinely absent) is a no-op.
        let target: Alarm?
        do {
            target = try await alarms.alarm(id: command.alarmID)
        } catch {
            return .rejected(
                reason: "We can’t check this alarm right now, so it’s left unchanged. "
                    + "Try again in a moment.")
        }
        guard let alarm = target else {
            return .authorized  // no such alarm to protect (a no-op cancel).
        }
        // Editing a non-critical alarm is not a destructive action to gate; only
        // weakening a critical one is.
        if case .update = command, alarm.criticality != .critical {
            return .authorized
        }
        // Commitment lock (WG-288/293, amends #6): inside the lock a destructive command is rejected
        // outright — no confirmation lifts it. `markChallengePassed` is non-destructive, so the wake
        // path is never blocked. The copy makes no duration claim (the bound is confidential).
        if await isCommitted(alarm) {
            return .rejected(
                reason: "This alarm is locked until you complete its walk. You can change it "
                    + "after you’re up, or before it locks next time.")
        }
        return decision(for: alarm, source: source, userConfirmed: userConfirmed)
    }

    /// Whether `alarm` is inside its commitment window (pre-fire lock, or the ring window of an
    /// unsatisfied pending wake). Pure rule in `CommitmentLock`; this just feeds it the engine-resolved
    /// next occurrence and the pending read.
    private func isCommitted(_ alarm: Alarm) async -> Bool {
        let fire =
            alarm.isEnabled
            ? engine.nextOccurrence(for: alarm, after: clock.now, deviceTimeZone: deviceTimeZone())
            : nil
        let pending = await pendingUnsatisfiedFireTime(alarm.id)
        return CommitmentLock.isLocked(
            alarm: alarm, nextFireTime: fire, pendingUnsatisfiedFireTime: pending, now: clock.now)
    }

    /// #31: the criticality change a model may not make. Returns a deny reason if `command`
    /// (from a model) would create a critical alarm or alter an alarm's criticality; `nil` if
    /// it leaves criticality untouched. Only ever consulted for an `.agentProposal` source.
    private func modelCriticalityChange(_ command: AlarmCommand) async -> String? {
        let reason =
            "An automated suggestion can’t change whether an alarm is critical. "
            + "Only you can, in the alarm’s settings."
        switch command {
        case .create(let alarm):
            return alarm.criticality == .critical ? reason : nil
        case .update(let alarm):
            let current = (try? await alarms.alarm(id: alarm.id))?.criticality ?? .standard
            return alarm.criticality != current ? reason : nil
        default:
            return nil  // enable/disable/delete/snooze/… don't carry a new criticality.
        }
    }

    private func decision(
        for alarm: Alarm, source: CommandSource, userConfirmed: Bool
    ) -> PolicyDecision {
        let critical = alarm.criticality == .critical
        if critical, source == .agentProposal {
            // #4: an automated proposal can never suppress a critical alarm — only a user.
            return .rejected(
                reason: "An automated suggestion can’t cancel or change a critical alarm. "
                    + "Do it yourself if you’re sure.")
        }
        if critical, !userConfirmed {
            // Confirmable (#6): the user can re-submit with confirmation. Distinct from the
            // #4 agent rejection above, which no confirmation can lift.
            return .needsConfirmation(
                reason: "This is a critical alarm. Confirm that you want to cancel or change it — "
                    + "it will no longer ring.")
        }
        if !critical, isImminent(alarm), !userConfirmed {
            return .needsConfirmation(
                reason: "This alarm is about to go off. Confirm that you want to cancel or "
                    + "change it.")
        }
        return .authorized
    }

    private func isDestructive(_ command: AlarmCommand) -> Bool {
        switch command {
        case .disable, .delete, .cancelOccurrence, .rescheduleOccurrence, .snooze, .update:
            return true
        case .create, .enable, .markChallengePassed, .keepOriginal, .reconcile, .recover:
            return false
        }
    }

    private func isImminent(_ alarm: Alarm) -> Bool {
        // A disabled alarm has no upcoming fire, so it is never "imminent" — the
        // scheduling engine deliberately ignores `isEnabled`, so gate it here (else a
        // disabled alarm inside the window would be falsely called "about to go off").
        guard alarm.isEnabled else { return false }
        guard
            let occurrence = engine.nextOccurrence(
                for: alarm, after: clock.now, deviceTimeZone: deviceTimeZone())
        else {
            return false
        }
        return occurrence.timeIntervalSince(clock.now) <= Self.imminentWindow
    }
}
