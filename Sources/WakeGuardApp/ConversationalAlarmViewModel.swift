import Foundation
import Observation

/// Drives the conversational alarm-creation flow (WG-166): parse the user's text (WG-164), validate the
/// result deterministically (WG-165), and show the **parsed schedule + assumptions** for review. It
/// **schedules nothing before confirmation** — the injected `commit` seam is invoked *only* from
/// `confirm()`, never during parsing — and a **manual editor is always one tap away** via
/// `requestManualEditor()`. It never sets criticality (#31) and, on any model failure, routes to the
/// manual editor (#33).
@MainActor
@Observable
final class ConversationalAlarmViewModel {

    /// The visible step of the flow.
    enum Stage: Sendable, Equatable {
        case idle
        case parsing
        case clarifying(AlarmClarification)
        /// A validated schedule awaiting the user's confirmation. Nothing is scheduled yet.
        case preview(ParsedScheduleSummary)
        case rejected(AlarmIntentRejection)
        /// The model was unavailable/refused — use the manual editor.
        case unavailable
        case scheduled
        /// Confirmed, but the scheduling command failed — the alarm was not created.
        case failed
    }

    var input = ""
    private(set) var stage: Stage = .idle
    /// Set when the user asks for the manual editor; the parent view presents `CreateAlarmView`.
    private(set) var manualEditorRequested = false

    private let parser: NaturalLanguageAlarmParser
    private let validator: AlarmIntentValidator
    private let clock: any WallClock
    private let deviceTimeZone: @Sendable () -> TimeZone
    private let commit: @Sendable (ValidatedAlarmIntent) async -> Bool
    /// The validated intent backing the current `.preview`, stashed for `confirm()`.
    private var pending: ValidatedAlarmIntent?

    init(
        parser: NaturalLanguageAlarmParser,
        validator: AlarmIntentValidator = AlarmIntentValidator(),
        clock: any WallClock, deviceTimeZone: @escaping @Sendable () -> TimeZone = { .current },
        commit: @escaping @Sendable (ValidatedAlarmIntent) async -> Bool
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

    /// Parse the current input and move to a preview, a clarification, a rejection, or the manual-editor
    /// fallback. Schedules nothing.
    func submit() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stage = .parsing
        pending = nil
        switch await parser.parse(text) {
        case .preview(let draft): resolve(draft)
        case .needsClarification(let clarification): stage = .clarifying(clarification)
        case .unavailable: stage = .unavailable
        }
    }

    /// Resolve a clarification the user picked (e.g. the AM or PM reading) into a preview or rejection.
    func choose(_ draft: AlarmDraftPreview) {
        resolve(draft)
    }

    /// Confirm the previewed schedule. This is the **only** path that schedules — it hands the validated
    /// intent to the command boundary (never AlarmKit/persistence directly, #1/#2).
    func confirm() async {
        guard case .preview = stage, let intent = pending else { return }
        let scheduled = await commit(intent)
        if scheduled {
            pending = nil
            stage = .scheduled
        } else {
            stage = .failed
        }
    }

    func requestManualEditor() {
        manualEditorRequested = true
    }

    private func resolve(_ draft: AlarmDraftPreview) {
        switch validator.validate(
            draft, timeZoneIdentifier: deviceTimeZone().identifier, now: clock.now)
        {
        case .valid(let intent):
            pending = intent
            stage = .preview(ParsedScheduleSummary.summary(for: intent))
        case .rejected(let reason):
            pending = nil
            stage = .rejected(reason)
        }
    }
}
