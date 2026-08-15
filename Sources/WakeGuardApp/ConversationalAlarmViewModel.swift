import Foundation
import Observation

/// Drives the conversational alarm-creation flow (WG-166 / WG-298): parse the user's text (WG-164),
/// validate the schedule deterministically (WG-165), then gather the enforcement choices it couldn't infer
/// — **critical or not**, **walk or not**, and the **steps + seconds** — asking only what the text didn't
/// already state, and finally show the full **preview** for an explicit confirm. It **schedules nothing
/// before confirmation** (the injected `commit` seam runs only from `confirm()`). Criticality is never taken
/// from the model's output (#31) — a deterministic keyword hint pre-fills a choice the user still confirms
/// in the review step (WG-298 ADR, amending WG-245 Finding A). A **manual editor is always one tap away**.
@MainActor
@Observable
final class ConversationalAlarmViewModel {

    /// The visible step of the flow.
    enum Stage: Sendable, Equatable {
        case idle
        case parsing
        case clarifying(AlarmClarification)
        /// Follow-up: make this a critical alarm? Asked only when the text didn't say so (WG-298).
        case askCritical
        /// Follow-up: require a walk to turn it off? Asked only when the text didn't say so (WG-298).
        case askWalk
        /// Follow-up: the walk's steps + seconds (the same bounded steppers as the manual editor, WG-298).
        case configureWalk
        /// A validated schedule + gathered choices awaiting the user's confirmation. Nothing scheduled yet.
        case preview(ParsedScheduleSummary)
        case rejected(AlarmIntentRejection)
        /// On-device intelligence is unavailable — use the manual editor.
        case unavailable
        /// The model ran but couldn't turn the text into an alarm — suggest rephrasing (or manual).
        case notUnderstood
        case scheduled
        /// Confirmed, but the scheduling command failed — the alarm was not created.
        case failed
    }

    var input = ""
    private(set) var stage: Stage = .idle
    /// The criticality the user has chosen/confirmed. Never set from the model — only from a keyword hint
    /// (pre-fill) plus the user's explicit answer/confirmation (#31 / WG-298).
    private(set) var isCritical = false
    /// The walk-challenge form state (steps + seconds), bound by the configure step — reusing the manual
    /// editor's bounded, cadence-normalized draft so a conversational walk stays within the same bounds.
    var challengeDraft = ChallengeDraft()
    /// The original request mentioned critical / walk — used to pre-fill and skip the matching question.
    private(set) var mentionedCriticality = false
    private(set) var mentionedWalk = false
    /// Set when the user asks for the manual editor; the parent view presents `CreateAlarmView`.
    private(set) var manualEditorRequested = false

    private let parser: NaturalLanguageAlarmParser
    private let validator: AlarmIntentValidator
    private let clock: any WallClock
    private let deviceTimeZone: @Sendable () -> TimeZone
    private let commit: @Sendable (ConversationalAlarmSpec) async -> Bool
    /// The validated schedule backing the current gathering/preview, stashed for `confirm()`.
    private var pending: ValidatedAlarmIntent?
    /// Which follow-ups are resolved (by inference or an answer), so each is asked at most once.
    private var criticalAnswered = false
    private var walkAnswered = false
    private var walkConfigured = false

    init(
        parser: NaturalLanguageAlarmParser,
        validator: AlarmIntentValidator = AlarmIntentValidator(),
        clock: any WallClock, deviceTimeZone: @escaping @Sendable () -> TimeZone = { .current },
        commit: @escaping @Sendable (ConversationalAlarmSpec) async -> Bool
    ) {
        self.parser = parser
        self.validator = validator
        self.clock = clock
        self.deviceTimeZone = deviceTimeZone
        self.commit = commit
    }

    var canConfirm: Bool {
        if case .preview = stage { return true }
        return false
    }

    /// Parse the current input, then gather the un-inferred enforcement choices. Schedules nothing.
    func submit() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stage = .parsing
        resetGathering()
        mentionedCriticality = Self.mentionsCriticality(text)
        mentionedWalk = Self.mentionsWalk(text)
        switch await parser.parse(text) {
        case .preview(let draft): resolve(draft)
        case .needsClarification(let clarification): stage = .clarifying(clarification)
        case .modelUnavailable: stage = .unavailable
        case .notUnderstood: stage = .notUnderstood
        }
    }

    /// Resolve a clarification the user picked (e.g. the AM or PM reading) into gathering or a rejection.
    func choose(_ draft: AlarmDraftPreview) {
        resolve(draft)
    }

    /// Answer the critical follow-up, then advance to the next un-resolved question.
    func answerCritical(_ wantsCritical: Bool) {
        guard case .askCritical = stage else { return }
        isCritical = wantsCritical
        criticalAnswered = true
        advance()
    }

    /// Answer the walk follow-up, then advance. Turning walk on routes to the steps/seconds step next.
    func answerWalk(_ wantsWalk: Bool) {
        guard case .askWalk = stage else { return }
        challengeDraft.kind = wantsWalk ? .walk : .none
        walkAnswered = true
        advance()
    }

    /// Accept the walk's steps + seconds (normalized into the plausible-cadence band), then advance.
    func confirmWalkConfiguration() {
        guard case .configureWalk = stage else { return }
        challengeDraft.normalizeSteps()
        walkConfigured = true
        advance()
    }

    /// Confirm the reviewed alarm. The **only** path that schedules — it hands the validated schedule plus
    /// the user-confirmed criticality and challenge to the command boundary (never AlarmKit/persistence
    /// directly, #1/#2).
    func confirm() async {
        guard case .preview = stage, let intent = pending else { return }
        // Clear pending *before* the await (WG-241): a concurrent second confirm() fails this guard, so a
        // proposal is committed at most once.
        pending = nil
        let spec = ConversationalAlarmSpec(
            intent: intent, criticality: isCritical ? .critical : .standard,
            challenge: challengeDraft.build())
        let scheduled = await commit(spec)
        stage = scheduled ? .scheduled : .failed
    }

    func requestManualEditor() {
        manualEditorRequested = true
    }

    // MARK: - inference (deterministic, never from the model — #31)

    /// Whether the request asked for a critical/important alarm (WG-296/298). Pre-fills the choice and
    /// skips the question; the user still confirms criticality in the preview.
    static func mentionsCriticality(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["critical", "important", "urgent"].contains { lowered.contains($0) }
    }

    /// Whether the request asked to require a walk (WG-298). Pre-fills walk-on and skips the walk question;
    /// the steps/seconds are still gathered and shown for confirmation.
    static func mentionsWalk(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["walk", "walking"].contains { lowered.contains($0) }
    }

    // MARK: - private

    private func resetGathering() {
        pending = nil
        isCritical = false
        challengeDraft = ChallengeDraft()
        criticalAnswered = false
        walkAnswered = false
        walkConfigured = false
    }

    private func resolve(_ draft: AlarmDraftPreview) {
        switch validator.validate(
            draft, timeZoneIdentifier: deviceTimeZone().identifier, now: clock.now)
        {
        case .valid(let intent):
            pending = intent
            // Apply deterministic hints from the original text: pre-fill the choice and skip its question.
            if mentionedCriticality {
                isCritical = true
                criticalAnswered = true
            }
            if mentionedWalk {
                challengeDraft.kind = .walk
                walkAnswered = true
            }
            advance()
        case .rejected(let reason):
            pending = nil
            stage = .rejected(reason)
        }
    }

    /// Move to the next un-resolved follow-up, or to the final preview when everything is gathered.
    private func advance() {
        guard let intent = pending else { return }
        if !criticalAnswered {
            stage = .askCritical
        } else if !walkAnswered {
            stage = .askWalk
        } else if challengeDraft.kind == .walk, !walkConfigured {
            stage = .configureWalk
        } else {
            stage = .preview(ParsedScheduleSummary.summary(for: intent))
        }
    }
}
