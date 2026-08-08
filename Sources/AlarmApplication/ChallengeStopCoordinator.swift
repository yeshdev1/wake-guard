import Foundation

/// Connects a valid wake-challenge pass to the authorized ring-stop (WG-073). Only a **terminal walk
/// pass** (`WakeChallengePhase.permitsAlarmDismissal`) or the **accessible alternative's completion**
/// (the authorized fallback) reaches a stop; each submits **exactly one** `markChallengePassed`
/// command through the `AlarmCommandProcessing` boundary — the only path to the AlarmKit adapter (#2),
/// where the policy engine authorizes it (#3), the outbox makes it idempotent, and it's audited (#46).
///
/// An `actor`, so the once-only guard is race-safe: concurrent / duplicate pass callbacks (a jittery
/// challenge, a UI event racing a notification action) serialize and emit **one** stop. A non-passing
/// phase never emits a stop — a movement inference alone never stops the alarm; only a terminal pass
/// or the authorized fallback does (#21 / #24).
actor ChallengeStopCoordinator {
    private let alarmID: AlarmID
    private let processor: any AlarmCommandProcessing
    private let source: CommandSource
    private let auditActor: AuditActor
    private var hasRequestedStop = false

    init(
        alarmID: AlarmID, processor: any AlarmCommandProcessing,
        source: CommandSource = .userInterface, auditActor: AuditActor = .user
    ) {
        self.alarmID = alarmID
        self.processor = processor
        self.source = source
        self.auditActor = auditActor
    }

    /// Whether a stop has already been requested — once true, further callbacks are ignored.
    var didRequestStop: Bool { hasRequestedStop }

    /// Call when the walk challenge reaches a phase. Emits the stop **only** for a terminal pass
    /// (`permitsAlarmDismissal`), and only once; any other phase is ignored (returns `nil`).
    @discardableResult
    func walkChallengeReached(_ phase: WakeChallengePhase) async -> CommandOutcome? {
        guard phase.permitsAlarmDismissal else { return nil }
        return await requestStopOnce()
    }

    /// Call when the accessible alternative is completed (the authorized non-walking fallback). Emits
    /// the stop once.
    @discardableResult
    func accessibleAlternativePassed() async -> CommandOutcome? {
        await requestStopOnce()
    }

    private func requestStopOnce() async -> CommandOutcome? {
        guard !hasRequestedStop else { return nil }
        hasRequestedStop = true
        return await processor.process(
            .markChallengePassed(alarmID), from: source, by: auditActor, userConfirmed: false)
    }
}
