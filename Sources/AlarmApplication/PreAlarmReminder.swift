import Foundation

/// Why a "remind me later" request produced no further reminder (WG-087). String-raw, fail-closed
/// (#27).
enum ReminderExhaustion: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// The per-criticality reminder cap was reached — no more re-prompts.
    case reachedCap
    /// A full deferral would land too close to (or past) the alarm — no safe window remains.
    case noSafeWindow
}

/// The result of a pre-alarm "remind me later" tap (WG-087): either re-show the prompt at a bounded
/// future instant, or stop reminding (capped, or no safe window before the alarm). It carries **no**
/// alarm change — remind-later defers the *prompt*, never the alarm (the schedule is untouched, #7/#8;
/// "critical alarms retain original schedule").
enum PreAlarmReminderPlan: Sendable, Equatable {
    /// Re-show the prompt at `at`; `remindersUsed` is the new running count for the caller to persist.
    case remind(at: Date, remindersUsed: Int)
    /// No further reminder.
    case exhausted(ReminderExhaustion)

    /// The reminder instant, when one was scheduled.
    var reminderTime: Date? {
        if case .remind(let at, _) = self { return at }
        return nil
    }
}

/// Computes the next pre-alarm reminder for a "remind me later" tap (WG-087). Pure and deterministic
/// (`now` / `alarmFireTime` injected); it returns a *prompt* time, holding no alarm authority, so it
/// can never change the alarm's schedule — a critical alarm always rings exactly when scheduled.
/// **Bounded**: a reminder is offered only if a full deferral fits with at least `minLeadBeforeAlarm`
/// to spare before the alarm, so the re-prompt can never extend beyond safe bounds. **Capped**: at
/// most `maxReminders(for:)` re-prompts, tighter for a critical alarm.
enum PreAlarmReminder {

    /// Tunable, **safe-bounds-clamped** config: the deferral interval, the per-criticality caps, and
    /// the minimum lead the re-prompt must leave before the alarm. The initializer clamps every value
    /// to a safe range (and a critical cap can never exceed the standard one), so no config can make a
    /// reminder unsafe.
    struct Config: Sendable, Equatable {
        let interval: TimeInterval
        let standardMaxReminders: Int
        let criticalMaxReminders: Int
        let minLeadBeforeAlarm: TimeInterval

        init(
            interval: TimeInterval, standardMaxReminders: Int, criticalMaxReminders: Int,
            minLeadBeforeAlarm: TimeInterval
        ) {
            func clamp(
                _ value: TimeInterval, _ lo: TimeInterval, _ hi: TimeInterval, _ fallback: Double
            )
                -> TimeInterval
            {
                guard value.isFinite else { return fallback }
                return min(max(value, lo), hi)
            }
            self.interval = clamp(interval, 60, 1800, 300)
            self.minLeadBeforeAlarm = clamp(minLeadBeforeAlarm, 30, 600, 120)
            let standard = max(0, min(standardMaxReminders, 5))
            self.standardMaxReminders = standard
            self.criticalMaxReminders = max(0, min(criticalMaxReminders, standard))
        }

        static let `default` = Config(
            interval: 300, standardMaxReminders: 3, criticalMaxReminders: 1, minLeadBeforeAlarm: 120
        )

        func maxReminders(for criticality: Criticality) -> Int {
            criticality == .critical ? criticalMaxReminders : standardMaxReminders
        }
    }

    /// The next reminder for a "remind me later" tap, given how many reminders were already used this
    /// prompt session. Returns `.exhausted` when the cap is reached or a full deferral wouldn't fit
    /// safely before the alarm; otherwise `.remind(at:)` a bounded interval from now.
    static func next(
        now: Date, alarmFireTime: Date, remindersUsed: Int, criticality: Criticality,
        config: Config = .default
    ) -> PreAlarmReminderPlan {
        // A corrupted / negative used-count fails closed — never reset the counter to grant extras.
        guard remindersUsed >= 0, remindersUsed < config.maxReminders(for: criticality) else {
            return .exhausted(.reachedCap)
        }
        // Fail closed on a non-finite clock / fire time (a NaN comparison is otherwise blind).
        guard now.timeIntervalSince1970.isFinite, alarmFireTime.timeIntervalSince1970.isFinite
        else {
            return .exhausted(.noSafeWindow)
        }
        let candidate = now.addingTimeInterval(config.interval)
        // The re-prompt must land at least `minLeadBeforeAlarm` before the alarm — a full deferral
        // that would push past that cutoff (or past the alarm itself) yields no reminder.
        let latestAllowed = alarmFireTime.addingTimeInterval(-config.minLeadBeforeAlarm)
        guard candidate <= latestAllowed else { return .exhausted(.noSafeWindow) }
        return .remind(at: candidate, remindersUsed: remindersUsed + 1)
    }
}
