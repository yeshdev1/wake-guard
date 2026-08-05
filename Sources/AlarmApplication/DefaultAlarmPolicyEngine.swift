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
    private let engine = AlarmSchedulingEngine()

    init(
        alarms: any AlarmRepository,
        clock: any WallClock,
        deviceTimeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.alarms = alarms
        self.clock = clock
        self.deviceTimeZone = deviceTimeZone
    }

    func authorize(
        _ command: AlarmCommand, from source: CommandSource, userConfirmed: Bool
    ) async -> PolicyDecision {
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
        return decision(for: alarm, source: source, userConfirmed: userConfirmed)
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
            return .rejected(
                reason: "This is a critical alarm. Confirm that you want to cancel or change it.")
        }
        if !critical, isImminent(alarm), !userConfirmed {
            return .rejected(
                reason: "This alarm is about to go off. Confirm that you want to cancel or "
                    + "change it.")
        }
        return .authorized
    }

    private func isDestructive(_ command: AlarmCommand) -> Bool {
        switch command {
        case .disable, .cancelOccurrence, .rescheduleOccurrence, .snooze, .update:
            return true
        case .create, .enable, .markChallengePassed, .reconcile, .recover:
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
