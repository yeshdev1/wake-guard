import Foundation

/// The user's **coarse** feedback on a pre-alarm prompt (WG-090). After a pre-alarm prompt (WG-083)
/// the user can indicate whether the nudge was a false positive ("I wasn't awake") or `helpful`. This
/// is a two-value category and nothing more — deliberately **not** a rating, a timestamp, a sleep
/// event, or any sensor value (#41). String-raw so an unknown persisted value fails to decode (#27).
enum PreAlarmFeedbackCategory: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// A false positive — the prompt appeared but the user was not actually awake.
    case notAwake
    /// The prompt was useful.
    case helpful
}

/// A **coarse, on-device tally** of pre-alarm feedback (WG-090) — just two non-negative counters, one
/// per `PreAlarmFeedbackCategory`. It stores **no** identifying or sensitive data: no alarm id, no
/// occurrence / fire time, no sleep-revealing timestamp, no raw motion/health/location sample (#41). It
/// is intentionally aggregate — an individual prompt's feedback is folded into a count and cannot be
/// recovered — so it reveals nothing about *when* the user slept or was prompted.
///
/// **Holds no alarm authority (the WG-090 safety property, structural).** This value references no
/// `Alarm`, `AlarmID`, `Criticality`, `AlarmCommand`, `ScheduleRule`, or `AwakeEvidenceModel.Config`,
/// so it has no path to whether/when a critical alarm rings or its safety gates. It may later inform an
/// *advisory* retune of the awake-evidence model (WG-080) — but only through explicit user action, never
/// a silent feedback-driven change (#8/#31). Recording feedback here can never mutate an alarm.
struct PreAlarmFeedbackCounts: Sendable, Equatable, Hashable, Codable {
    /// How many times the user reported a false positive ("I wasn't awake").
    let notAwakeCount: Int
    /// How many times the user reported the prompt was helpful.
    let helpfulCount: Int

    /// A fresh, empty tally.
    static let empty = PreAlarmFeedbackCounts(notAwakeCount: 0, helpfulCount: 0)

    /// Construct a tally, **clamping each count at zero** so a decoded or hand-built negative can never
    /// appear (a count is a non-negative frequency by construction; mirrors the re-clamp-on-construct
    /// pattern used across the domain).
    init(notAwakeCount: Int, helpfulCount: Int) {
        self.notAwakeCount = max(0, notAwakeCount)
        self.helpfulCount = max(0, helpfulCount)
    }

    /// Re-run the clamping initializer on decode, so no Codable path can smuggle in a negative count.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            notAwakeCount: try container.decode(Int.self, forKey: .notAwakeCount),
            helpfulCount: try container.decode(Int.self, forKey: .helpfulCount))
    }

    /// The tally after recording one more `category`, **saturating** at `Int.max` rather than trapping
    /// on overflow (a pure value transform — no store, no clock, no alarm; deterministic and testable).
    func recording(_ category: PreAlarmFeedbackCategory) -> PreAlarmFeedbackCounts {
        switch category {
        case .notAwake:
            return PreAlarmFeedbackCounts(
                notAwakeCount: Self.increment(notAwakeCount), helpfulCount: helpfulCount)
        case .helpful:
            return PreAlarmFeedbackCounts(
                notAwakeCount: notAwakeCount, helpfulCount: Self.increment(helpfulCount))
        }
    }

    private static func increment(_ value: Int) -> Int {
        let (sum, overflow) = value.addingReportingOverflow(1)
        return overflow ? Int.max : sum
    }
}

/// A **local, coarse** store of pre-alarm feedback (WG-090). The user indicates "I wasn't awake" or
/// "helpful" after a prompt; the store folds it into an on-device `PreAlarmFeedbackCounts` tally. It is
/// deliberately minimal: `record` a category, `counts` reads the aggregate — there is **no** per-event
/// read, no timestamp, no alarm id, so it cannot reconstruct when the user slept (#41/#43).
///
/// **Holds no alarm authority (structural, tested).** The port speaks only `PreAlarmFeedbackCategory`
/// and `PreAlarmFeedbackCounts` — no `Alarm`, `AlarmID`, `AlarmCommand`, adapter, or alarm-persistence
/// type — so recording feedback can never cancel, delay, reschedule, or retune a critical alarm. Any
/// advisory use of the tally (e.g. tuning WG-080) is a separate, explicit, user-initiated step; the
/// store itself never feeds scheduling or criticality, so it **cannot silently retune critical
/// behavior** (#8/#31). `record` is best-effort: a store fault drops the coarse feedback and the alarm
/// is unaffected either way.
protocol PreAlarmFeedbackStore: Sendable {
    /// Record one coarse feedback category. Best-effort and non-throwing — feedback is advisory, so a
    /// storage fault silently drops it rather than surfacing an error (the alarm is never affected).
    func record(_ category: PreAlarmFeedbackCategory) async
    /// The current aggregate tally (or `.empty` if none recorded / unreadable).
    func counts() async -> PreAlarmFeedbackCounts
}
