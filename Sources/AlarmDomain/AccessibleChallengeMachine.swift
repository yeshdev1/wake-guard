import Foundation

/// The phase of the accessible (non-walking) alternative challenge (WG-072). String-raw so an
/// unknown persisted value fails to decode (#27). Like the walk, it only ever reaches `.passed` — a
/// released/reset gesture returns to `.idle`; it never *fails* a challenge (the alarm stays active
/// until passed, #21).
enum AccessibleChallengePhase: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case idle
    case inProgress
    case passed
}

/// Requirements for the accessible alternative (WG-072), **clamped** so the gesture stays a
/// *deliberate* manual action (never passable by a single accidental touch) yet remains *completable*
/// by someone with limited mobility. The user preselects the `AccessibleChallenge` kind in the
/// create/edit flow (WG-045); the runtime honors it.
struct AccessibleChallengeRequirements: Sendable, Equatable {
    let kind: AccessibleChallenge
    let requiredTaps: Int
    let minTapInterval: TimeInterval
    let holdDuration: TimeInterval

    static let requiredTapsFloor = 4
    static let requiredTapsCeiling = 12
    /// Debounce: taps closer than this are ignored, so a held / auto-repeating touch can't rack up
    /// the count — the user must make distinct taps. Fast enough to stay comfortable.
    static let defaultMinTapInterval: TimeInterval = 0.15
    static let holdDurationFloor: TimeInterval = 2
    static let holdDurationCeiling: TimeInterval = 8

    init(kind: AccessibleChallenge, requiredTaps: Int = 6, holdDuration: TimeInterval = 3) {
        self.kind = kind
        self.requiredTaps = min(Self.requiredTapsCeiling, max(Self.requiredTapsFloor, requiredTaps))
        self.minTapInterval = Self.defaultMinTapInterval
        self.holdDuration =
            holdDuration.isFinite
            ? min(Self.holdDurationCeiling, max(Self.holdDurationFloor, holdDuration))
            : Self.holdDurationFloor
    }
}

/// The deterministic accessible-alternative runtime (WG-072): a user who can't walk passes the same
/// challenge with a deliberate manual gesture — a debounced **tap sequence** or a **press-and-hold**.
/// It advances **only** through explicit user-input events (`tap` / `beginHold` / `holdTick` /
/// `endHold`), reads no clock of its own, and has no model / AI seam — so, exactly as AI cannot call
/// AlarmKit (#1), **AI can neither invoke nor complete it** (it can't emit touches). Passing the
/// accessible alternative is equivalent to passing the walk; only then may the alarm be dismissed
/// (#21). Pure value type — deterministic and fully testable.
struct AccessibleChallengeMachine: Sendable, Equatable {
    let requirements: AccessibleChallengeRequirements
    private(set) var phase: AccessibleChallengePhase = .idle
    private(set) var acceptedTaps = 0
    private var lastTapTime: Date?
    private var holdStart: Date?

    init(_ requirements: AccessibleChallengeRequirements) {
        self.requirements = requirements
    }

    var isPassed: Bool { phase == .passed }

    /// Tap-sequence progress toward the required count (0…1).
    var tapFraction: Double {
        min(1, Double(acceptedTaps) / Double(requirements.requiredTaps))
    }

    /// Register a deliberate tap (tap-sequence kind). **Debounced**: a tap within `minTapInterval` of
    /// the last accepted one, an out-of-order timestamp, or a non-finite time is ignored, so a held /
    /// auto-repeating touch can't satisfy the sequence. Returns whether the tap was accepted.
    @discardableResult
    mutating func tap(at time: Date) -> Bool {
        guard requirements.kind == .tapSequence, phase != .passed,
            time.timeIntervalSince1970.isFinite
        else { return false }
        if let last = lastTapTime,
            time < last || time.timeIntervalSince(last) < requirements.minTapInterval
        {
            return false
        }
        lastTapTime = time
        acceptedTaps += 1
        phase = acceptedTaps >= requirements.requiredTaps ? .passed : .inProgress
        return true
    }

    /// Begin a press-and-hold.
    mutating func beginHold(at time: Date) {
        guard requirements.kind == .pressAndHold, phase != .passed,
            time.timeIntervalSince1970.isFinite
        else { return }
        holdStart = time
        phase = .inProgress
    }

    /// A while-held progress check (a timer tick): pass once the hold has lasted long enough.
    mutating func holdTick(at time: Date) {
        guard requirements.kind == .pressAndHold, phase == .inProgress, let start = holdStart,
            time.timeIntervalSince1970.isFinite
        else { return }
        if time.timeIntervalSince(start) >= requirements.holdDuration { phase = .passed }
    }

    /// The hold was released. Passes if the required duration was met; otherwise resets to `.idle` (a
    /// released-early hold is safe — the alarm stays active).
    mutating func endHold(at time: Date) {
        guard requirements.kind == .pressAndHold, phase != .passed else { return }
        if let start = holdStart, time.timeIntervalSince1970.isFinite,
            time.timeIntervalSince(start) >= requirements.holdDuration
        {
            phase = .passed
        } else {
            holdStart = nil
            phase = .idle
        }
    }

    /// Complete a press-and-hold via an explicit **accessible activation** — e.g. a VoiceOver /
    /// Switch Control / Voice Control double-tap, the equivalent of holding for someone who can't
    /// sustain a press. It is still a deliberate user-input event routed through assistive tech
    /// (which AI cannot drive, #1), so it neither weakens the anti-AI property nor is reachable by a
    /// sighted touch user (who performs the real hold). No-op for a tap sequence.
    mutating func completeViaAccessibleActivation() {
        guard requirements.kind == .pressAndHold, phase != .passed else { return }
        phase = .passed
    }

    /// Press-and-hold progress at `now` (0…1) — for the view's ring/bar.
    func holdFraction(at now: Date) -> Double {
        guard requirements.kind == .pressAndHold, let start = holdStart,
            now.timeIntervalSince1970.isFinite
        else { return isPassed ? 1 : 0 }
        return min(1, max(0, now.timeIntervalSince(start) / requirements.holdDuration))
    }
}
