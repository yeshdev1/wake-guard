import Foundation

/// The phase of the deterministic wake challenge (WG-068). String-raw so an unknown persisted value
/// fails to decode (#27) rather than being trusted. The challenge is deterministic — no AI, and a
/// movement inference *alone* never fails it — and every terminal phase except `.passed` keeps the
/// alarm active (the safe fallback; #21, SCOPE §2.3).
enum WakeChallengePhase: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// Not started.
    case idle
    /// Requested; setting up sensors / permission.
    case starting
    /// Running and accumulating verified progress.
    case active
    /// Completed successfully — the only outcome that permits dismissing the alarm.
    case passed
    /// Explicitly failed (interrupted / abandoned unrecoverably). Alarm stays active.
    case failed
    /// The time limit elapsed without passing. Alarm stays active.
    case timedOut
    /// Sensors / permission unavailable — the challenge cannot run; offer the accessible
    /// alternative. Alarm stays active.
    case unavailable

    /// A terminal phase — no further progress; only a `reset` (re-arm) leaves it.
    var isTerminal: Bool {
        switch self {
        case .passed, .failed, .timedOut, .unavailable: return true
        case .idle, .starting, .active: return false
        }
    }

    /// Whether reaching this phase permits dismissing the alarm. **Only** `.passed` does — a failed,
    /// timed-out, unavailable, or still-running challenge always keeps the alarm active (#21).
    var permitsAlarmDismissal: Bool { self == .passed }
}

/// Monotonic-or-safely-reset progress toward the challenge target (WG-068). Progress is
/// `max(observed) - baseline` over the **cumulative** source counts observed during the run — a pure
/// function of the *peak* seen, which makes it monotonic and **inflation-proof by construction**: a
/// replayed or duplicate value can't raise the peak, and a counter reset (a dip) can't add (a later
/// climb only counts once it passes the prior peak). This mirrors the motion stack's contract —
/// `PedometerSample.stepCount` is cumulative and "a consumer computes progress from differences and
/// must be robust to duplicate/replayed samples so they cannot inflate it". Overflow-safe: a
/// garbage-huge value saturates at `required`, never traps (no crash on the dismissal path). A pause
/// resets cleanly to zero (a *safe* reset — the user re-earns it).
struct ChallengeProgress: Sendable, Equatable, Hashable {
    /// The target (e.g. required steps). Always ≥ 1 — a degenerate zero-target challenge can't
    /// auto-pass.
    let required: Int
    /// The cumulative source count at the run's start (first observation); progress is measured from
    /// here.
    private var baseline: Int?
    /// The highest cumulative count seen — the peak that drives progress (never decreases).
    private var peak: Int?

    init(required: Int) {
        self.required = max(1, required)
    }

    /// Verified progress so far: the peak count minus the baseline, clamped to `[0, required]`.
    /// Overflow-safe — an implausible span saturates at `required` rather than trapping.
    var completed: Int {
        guard let baseline, let peak else { return 0 }
        let (span, overflowed) = peak.subtractingReportingOverflow(baseline)
        return overflowed ? required : min(required, max(0, span))
    }

    var isComplete: Bool { completed >= required }
    var fraction: Double { min(1, Double(completed) / Double(required)) }

    /// Record a **cumulative** observed count (e.g. steps since the source began). The first sets the
    /// baseline; each raises the peak. Because progress is peak − baseline, a duplicate/replayed or
    /// reset-then-climb value can never inflate it.
    mutating func observe(cumulative: Int) {
        if baseline == nil { baseline = cumulative }
        peak = Swift.max(peak ?? cumulative, cumulative)
    }

    /// A safe reset — clears the baseline and peak (progress returns to zero); used on a pause.
    mutating func reset() {
        baseline = nil
        peak = nil
    }
}

/// An event driving the wake-challenge state machine.
enum WakeChallengeEvent: Sendable, Equatable {
    case start
    case sensorsReady
    case sensorsUnavailable
    /// A **cumulative** source count (e.g. steps since the source began) — not a raw delta, so
    /// replays can't inflate progress (see `ChallengeProgress`).
    case observedProgress(cumulative: Int)
    case pause
    case timeout
    case fail
    case reset
}

/// The deterministic wake-challenge state machine (WG-068): a phase + progress advanced only by
/// **valid** transitions. An invalid event is a no-op (the state is never corrupted), progress is
/// monotonic within an active run and safely reset on a pause, and every terminal phase except
/// `.passed` keeps the alarm active. Pure and deterministic — it reads no clock; the caller supplies
/// timeout / progress events.
struct WakeChallengeMachine: Sendable, Equatable {
    private(set) var phase: WakeChallengePhase
    private(set) var progress: ChallengeProgress

    init(required: Int) {
        phase = .idle
        progress = ChallengeProgress(required: required)
    }

    /// Apply an event. Returns `true` if it was a valid transition (state may have changed), `false`
    /// if the event was not valid in the current phase (state unchanged — only valid transitions are
    /// possible).
    @discardableResult
    mutating func apply(_ event: WakeChallengeEvent) -> Bool {
        switch (phase, event) {
        case (.idle, .start):
            phase = .starting
        case (.idle, .sensorsUnavailable), (.starting, .sensorsUnavailable),
            (.active, .sensorsUnavailable):
            phase = .unavailable
        case (.starting, .sensorsReady):
            phase = .active
        case (.starting, .timeout), (.active, .timeout):
            phase = .timedOut
        case (.starting, .fail), (.active, .fail):
            phase = .failed
        case (.active, .observedProgress(let cumulative)):
            progress.observe(cumulative: cumulative)
            if progress.isComplete { phase = .passed }
        case (.active, .pause):
            progress.reset()
        case (.passed, .reset), (.failed, .reset), (.timedOut, .reset), (.unavailable, .reset):
            phase = .idle
            progress.reset()
        default:
            return false
        }
        return true
    }
}
