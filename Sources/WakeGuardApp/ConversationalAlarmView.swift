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

            if model.mentionedCriticality {
                Label {
                    Text(
                        "This creates a standard alarm. To make it critical or add a walk challenge, "
                            + "open it in the editor after creating.")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityIdentifier("conversationalCriticalityNote")
            }

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
        case .unsupportedRecurrence: "I can’t set that repeat pattern. Try the manual editor."
        case .unsafeValue: "That request is out of range. Try the manual editor."
        }
    }
}
