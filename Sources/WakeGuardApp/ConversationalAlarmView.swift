import SwiftUI

/// The conversational alarm-creation screen (WG-166). The user types a request; the view shows the
/// **parsed schedule and the assumptions** behind it and requires an explicit **Confirm** — nothing is
/// scheduled before that. A **manual editor is always one tap away** (every state shows "Enter manually").
/// Design-system only, no color-only signals, VoiceOver-labelled; times render with the user's 12/24-hour
/// setting via `Text(_:format:)`.
struct ConversationalAlarmView: View {
    @Bindable var model: ConversationalAlarmViewModel
    /// Presents the manual `CreateAlarmView` fallback — wired by the parent.
    var onManualEditor: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            requestField
            stageContent
            Spacer(minLength: 0)
            manualEditorButton
        }
        .padding(DesignSystem.Spacing.lg)
        .onChange(of: model.manualEditorRequested) { _, requested in
            if requested { onManualEditor() }
        }
    }

    private var requestField: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Describe your alarm")
                .font(DesignSystem.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            TextField("e.g. wake me at 7 tomorrow", text: $model.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("conversationalAlarmInput")
            Button("Set up") { Task { await model.submit() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("conversationalAlarmSubmit")
        }
    }

    @ViewBuilder private var stageContent: some View {
        switch model.stage {
        case .idle:
            EmptyView()
        case .parsing:
            ProgressView("Reading your request…").accessibilityIdentifier("conversationalParsing")
        case .clarifying(let clarification):
            clarificationView(clarification)
        case .askCritical:
            choiceView(
                FollowUpChoice(
                    question: "Make this a critical alarm?",
                    detail:
                        "Critical alarms ring through silent mode and Focus, and are harder to dismiss.",
                    yes: "Yes, critical", no: "No, standard", id: "conversationalAskCritical"),
                onYes: { model.answerCritical(true) }, onNo: { model.answerCritical(false) })
        case .askWalk:
            choiceView(
                FollowUpChoice(
                    question: "Require a walk to turn it off?",
                    detail:
                        "You'll need to take a few steps to stop the alarm — a tap alternative is "
                        + "always available.",
                    yes: "Yes, add a walk", no: "No", id: "conversationalAskWalk"),
                onYes: { model.answerWalk(true) }, onNo: { model.answerWalk(false) })
        case .configureWalk:
            walkConfigView
        case .preview(let summary):
            previewView(summary)
        case .rejected(let reason):
            noticeView(
                rejectionText(reason), icon: "exclamationmark.triangle",
                id: "conversationalRejected")
        case .unavailable:
            noticeView(
                "Smart setup isn’t available right now. Turn on Apple Intelligence in Settings, or enter "
                    + "your alarm manually below.",
                icon: "wand.and.stars.inverse", id: "conversationalUnavailable")
        case .notUnderstood:
            noticeView(
                "I couldn’t turn that into an alarm. Try rephrasing — for example “wake me at 7 "
                    + "tomorrow” — or enter it manually below.",
                icon: "text.badge.questionmark", id: "conversationalNotUnderstood")
        case .scheduled:
            noticeView("Alarm created.", icon: "checkmark.circle", id: "conversationalScheduled")
        case .failed:
            noticeView(
                "I couldn’t create the alarm. Please try the manual editor.",
                icon: "exclamationmark.triangle", id: "conversationalFailed")
        }
    }

    // MARK: clarification

    @ViewBuilder private func clarificationView(_ clarification: AlarmClarification) -> some View {
        switch clarification {
        case .missingTime:
            noticeView(
                "What time should it ring? Add a time to your request.",
                icon: "clock", id: "conversationalMissingTime")
        case .meridiem(let morning, let evening):
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Did you mean morning or evening?")
                    .font(DesignSystem.Typography.cardTitle)
                Button {
                    model.choose(morning)
                } label: {
                    Text(
                        timeDate(hour: morning.hour, minute: morning.minute),
                        format: .dateTime.hour().minute())
                }
                .accessibilityIdentifier("conversationalMeridiemMorning")
                Button {
                    model.choose(evening)
                } label: {
                    Text(
                        timeDate(hour: evening.hour, minute: evening.minute),
                        format: .dateTime.hour().minute())
                }
                .accessibilityIdentifier("conversationalMeridiemEvening")
            }
        }
    }

    // MARK: preview + confirm

    @ViewBuilder private func previewView(_ summary: ParsedScheduleSummary) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Here’s what I’ll set")
                .font(DesignSystem.Typography.cardTitle)
            Label {
                Text(
                    timeDate(hour: summary.time.hour, minute: summary.time.minute),
                    format: .dateTime.hour().minute())
            } icon: {
                Image(systemName: "alarm")
            }
            .accessibilityIdentifier("conversationalPreviewTime")

            ForEach(Array(summary.assumptions.enumerated()), id: \.offset) { _, assumption in
                assumptionRow(assumption)
            }

            Label {
                Text(model.isCritical ? "Critical alarm" : "Standard alarm")
            } icon: {
                Image(systemName: model.isCritical ? "exclamationmark.triangle.fill" : "bell")
            }
            .font(DesignSystem.Typography.secondary)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            .accessibilityIdentifier("conversationalPreviewCriticality")

            Label {
                Text(walkSummaryText)
            } icon: {
                Image(systemName: "figure.walk")
            }
            .font(DesignSystem.Typography.secondary)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            .accessibilityIdentifier("conversationalPreviewWalk")

            Text("Nothing is scheduled until you confirm.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)

            Button("Confirm") { Task { await model.confirm() } }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("conversationalConfirm")
        }
    }

    @ViewBuilder private func assumptionRow(_ assumption: ScheduleAssumption) -> some View {
        switch assumption {
        case .usesCurrentTimeZone(let identifier):
            assumptionLabel("Time zone: \(identifier)", icon: "globe")
        case .ringsOn(let date):
            Label {
                Text(date, format: .dateTime.weekday(.wide).month().day())
            } icon: {
                Image(systemName: "calendar")
            }
            .accessibilityIdentifier("conversationalAssumptionDate")
        case .repeatsWeekly(let days):
            assumptionLabel(weekdaysText(days), icon: "repeat")
        }
    }

    // MARK: shared

    private func assumptionLabel(_ text: String, icon: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon)
        }
        .font(DesignSystem.Typography.secondary)
        .foregroundStyle(DesignSystem.Colors.secondaryText)
    }

    private func noticeView(_ text: String, icon: String, id: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon)
        }
        .font(DesignSystem.Typography.body)
        .accessibilityIdentifier(id)
    }

    private var manualEditorButton: some View {
        Button("Enter manually") { model.requestManualEditor() }
            .accessibilityIdentifier("conversationalManualEditor")
            .accessibilityHint("Opens the standard alarm editor")
    }

    private func timeDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }

    private func weekdaysText(_ days: Set<AIWeekday>) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let ordered = AIWeekday.allCases.filter(days.contains)
        let names = ordered.compactMap { day -> String? in
            guard let index = AIWeekday.allCases.firstIndex(of: day),
                symbols.indices.contains(index)
            else { return nil }
            return symbols[index]
        }
        return names.joined(separator: ", ")
    }

    private func rejectionText(_ reason: AlarmIntentRejection) -> String {
        switch reason {
        case .invalidTimeZone: "That time zone isn’t valid. Try the manual editor."
        case .timeOutOfRange: "That time isn’t valid."
        case .inThePast: "That time is in the past. Pick a future time."
        case .unsafeValue: "That request is out of range. Try the manual editor."
        }
    }
}

/// The static copy for a yes/no follow-up (WG-298), bundled so the view helper stays under the parameter
/// limit and the two questions read the same.
private struct FollowUpChoice {
    let question: String
    let detail: String
    let yes: String
    let no: String
    let id: String
}

/// The WG-298 follow-up screens — kept in an extension so the main view type stays within its body-length
/// budget.
extension ConversationalAlarmView {

    /// A yes/no follow-up — critical, or walk. Only shown for a dimension the request didn't already state.
    fileprivate func choiceView(
        _ choice: FollowUpChoice, onYes: @escaping () -> Void, onNo: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(choice.question).font(DesignSystem.Typography.cardTitle)
            Text(choice.detail)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
            Button(choice.yes, action: onYes)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("\(choice.id)Yes")
            Button(choice.no, action: onNo)
                .accessibilityIdentifier("\(choice.id)No")
        }
        .accessibilityIdentifier(choice.id)
    }

    /// The walk's steps + seconds — the same bounded steppers as the manual editor. Changing the duration
    /// re-bounds the step count so the required cadence stays in the plausible-walk band.
    fileprivate var walkConfigView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("How should the walk work?").font(DesignSystem.Typography.cardTitle)
            Stepper(
                "Walk for \(model.challengeDraft.durationSeconds) seconds",
                value: $model.challengeDraft.durationSeconds, in: ChallengeDraft.durationRange,
                step: 5
            )
            .accessibilityIdentifier("conversationalWalkDuration")
            .onChange(of: model.challengeDraft.durationSeconds) {
                model.challengeDraft.normalizeSteps()
            }
            Stepper(
                "At least \(model.challengeDraft.minimumSteps) steps",
                value: $model.challengeDraft.minimumSteps,
                in: ChallengeDraft.stepsBounds(forDuration: model.challengeDraft.durationSeconds)
            )
            .accessibilityIdentifier("conversationalWalkSteps")
            Button("Next") { model.confirmWalkConfiguration() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("conversationalWalkNext")
        }
        .accessibilityIdentifier("conversationalConfigureWalk")
    }

    /// The preview's walk line — the confirmed steps + seconds, or that a tap turns it off.
    fileprivate var walkSummaryText: String {
        guard model.challengeDraft.kind == .walk else { return "Turn off with a tap (no walk)" }
        return "Walk \(model.challengeDraft.minimumSteps) steps in "
            + "\(model.challengeDraft.durationSeconds) seconds to turn it off"
    }
}
