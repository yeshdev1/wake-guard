import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// The wake-up math puzzle screen (WG-308) — the accessible alternative to the walk (#22), presented when a
/// user who can't walk chooses "another way", and a genuine sleep-inertia breaker. A two-digit × single-digit
/// problem, a big custom number pad (usable while the alarm is alerting, without the system keyboard), a wrong
/// answer simply hands over a new problem (never a dead-end, #21). Fully accessible: the problem is spoken as
/// words, the entry and progress are announced, feedback is text **and** icon (never color alone). Pure
/// presentation; the machine advances only on this typed input, and there is no AI path to it (#1).
struct MathPuzzleView: View {
    let viewModel: MathPuzzleViewModel

    private let padRows: [[PadKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.delete, .digit(0), .enter],
    ]

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            header
            problem
            entryField
            feedback
            Spacer(minLength: DesignSystem.Spacing.sm)
            numberPad
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.screenBackground)
        .accessibilityIdentifier("mathPuzzleView")
        .onChange(of: viewModel.isPassed) { _, passed in
            if passed { announce(viewModel.passedAnnouncement, priority: .high) }
        }
    }

    private var header: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Text(viewModel.title)
                .font(DesignSystem.Typography.screenTitle)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("mathPuzzleTitle")
            Text(viewModel.instruction)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .multilineTextAlignment(.center)
            progress
        }
    }

    private var progress: some View {
        ProgressView(value: viewModel.progressFraction)
            .tint(DesignSystem.Colors.accent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Progress")
            .accessibilityValue(viewModel.progressText)
            .accessibilityIdentifier("mathPuzzleProgress")
    }

    private var problem: some View {
        Text(viewModel.current.prompt)
            .font(DesignSystem.Typography.screenTitle)
            .monospacedDigit()
            .accessibilityLabel(viewModel.problemAccessibilityLabel)
            .accessibilityIdentifier("mathPuzzleProblem")
    }

    private var entryField: some View {
        Text(viewModel.entry.isEmpty ? " " : viewModel.entry)
            .font(DesignSystem.Typography.screenTitle)
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.md)
            .background(
                DesignSystem.Colors.surface,
                in: RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
            )
            .accessibilityLabel("Your answer")
            .accessibilityValue(viewModel.entry.isEmpty ? "empty" : viewModel.entry)
            .accessibilityIdentifier("mathPuzzleEntry")
    }

    @ViewBuilder private var feedback: some View {
        if let text = viewModel.feedbackText {
            Label(
                text,
                systemImage: viewModel.lastResult == .correct
                    ? "checkmark.circle" : "arrow.clockwise"
            )
            .font(DesignSystem.Typography.controlLabel)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            .accessibilityIdentifier("mathPuzzleFeedback")
        }
    }

    private var numberPad: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ForEach(Array(padRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(row) { key in PadButton(key: key, viewModel: viewModel) }
                }
            }
        }
        .accessibilityIdentifier("mathPuzzlePad")
    }

    private func announce(_ message: String, priority: UIAccessibilityPriority = .default) {
        #if canImport(UIKit)
            let announcement = NSAttributedString(
                string: message, attributes: [.accessibilitySpeechAnnouncementPriority: priority])
            UIAccessibility.post(notification: .announcement, argument: announcement)
        #endif
    }
}

/// One key of the number pad — a digit, delete, or enter.
private enum PadKey: Identifiable, Equatable {
    case digit(Int)
    case delete
    case enter

    var id: String {
        switch self {
        case .digit(let value): "d\(value)"
        case .delete: "del"
        case .enter: "enter"
        }
    }
}

/// A single number-pad button; large hit target, clear label, VoiceOver-friendly.
private struct PadButton: View {
    let key: PadKey
    @Bindable var viewModel: MathPuzzleViewModel

    var body: some View {
        Button(action: act) { label }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.md)
            .background(background, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.control))
            .contentShape(Rectangle())
            .disabled(isDisabled)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private var label: some View {
        switch key {
        case .digit(let value):
            Text(String(value))
                .font(DesignSystem.Typography.screenTitle)
                .monospacedDigit()
                .foregroundStyle(DesignSystem.Colors.primaryText)
        case .delete:
            Image(systemName: "delete.left")
                .font(DesignSystem.Typography.controlLabel)
                .foregroundStyle(DesignSystem.Colors.primaryText)
        case .enter:
            Text("Enter")
                .font(DesignSystem.Typography.controlLabel)
                .foregroundStyle(DesignSystem.Colors.onFilled)
        }
    }

    private var background: Color {
        switch key {
        case .enter: DesignSystem.Colors.accent
        default: DesignSystem.Colors.surface
        }
    }

    private var isDisabled: Bool {
        key == .enter && !viewModel.canSubmit
    }

    private var accessibilityLabel: String {
        switch key {
        case .digit(let value): String(value)
        case .delete: "Delete"
        case .enter: "Enter"
        }
    }

    private var identifier: String {
        switch key {
        case .digit(let value): "mathPad\(value)"
        case .delete: "mathPadDelete"
        case .enter: "mathPadEnter"
        }
    }

    private func act() {
        switch key {
        case .digit(let value): viewModel.append(value)
        case .delete: viewModel.deleteLast()
        case .enter: viewModel.submit()
        }
    }
}
