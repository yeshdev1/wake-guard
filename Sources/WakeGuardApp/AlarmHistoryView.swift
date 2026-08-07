import SwiftUI

/// The per-alarm history / audit detail (WG-048). Read-only: it shows who and what changed an
/// alarm and when, distinguishes recovery/system actions from ordinary edits (#50), and never
/// exposes internal fingerprints (#41). Reads the audit repository from the composed
/// environment; a nil environment shows an explicit safe state rather than an empty list.
struct AlarmHistoryView: View {
    let alarmID: AlarmID
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        Group {
            if let environment {
                AlarmHistoryScreen(
                    audit: environment.auditRepository, clock: environment.clock, alarmID: alarmID)
            } else {
                AlarmListMessageView(
                    systemImage: "externaldrive.badge.exclamationmark",
                    title: "History unavailable",
                    message: "WakeGuard couldn’t open local storage, so this alarm’s history isn’t "
                        + "available. Reopen the app to try again.",
                    identifier: "historyUnavailable")
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AlarmHistoryScreen: View {
    @State private var model: AlarmHistoryViewModel

    init(audit: any AuditRepository, clock: any WallClock, alarmID: AlarmID) {
        _model = State(
            wrappedValue: AlarmHistoryViewModel(audit: audit, clock: clock, alarmID: alarmID))
    }

    var body: some View {
        content.task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            AlarmListMessageView(
                progress: true, title: "Loading history…", message: "", identifier: "historyLoading"
            )
        case .empty:
            AlarmListMessageView(
                systemImage: "clock.arrow.circlepath", title: "No history yet",
                message: "Changes to this alarm will appear here.", identifier: "historyEmpty")
        case .failed(let reason):
            AlarmListMessageView(
                systemImage: "exclamationmark.triangle", title: "Couldn’t load history",
                message: reason, identifier: "historyFailed")
        case .loaded(let items):
            List(items) { item in
                NavigationLink {
                    AuditEventDetailView(item: item)
                } label: {
                    AlarmHistoryRow(item: item)
                }
            }
            .accessibilityIdentifier("alarmHistoryList")
        }
    }
}

/// One history row: what changed, who + when, and a system/outcome tag line. The whole row is a
/// single combined VoiceOver phrase (a system action announced first). The tags reflow to a second
/// line at large Dynamic Type so the outcome (the non-color signal) is never truncated.
private struct AlarmHistoryRow: View {
    let item: AlarmHistoryItem

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: item.isSystem ? "arrow.triangle.2.circlepath" : "person")
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(item.what).font(DesignSystem.Typography.cardTitle)
                Text("\(item.who) · \(item.when)")
                    .font(DesignSystem.Typography.secondary)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DesignSystem.Spacing.sm) { tags }
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) { tags }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityIdentifier("alarmHistoryRow")
    }

    @ViewBuilder private var tags: some View {
        if item.isSystem {
            TagLabel(text: "System", systemImage: "gearshape")
        }
        TagLabel(text: outcomeText(item.outcome), systemImage: outcomeIcon(item.outcome))
    }
}

/// The full detail for one recorded change — safe fields only (no state hashes / correlation id).
private struct AuditEventDetailView: View {
    let item: AlarmHistoryItem

    var body: some View {
        List {
            LabeledContent("What", value: item.what)
            LabeledContent("Who", value: item.who)
            LabeledContent("When", value: item.whenDetailed)
            // A system action's origin is already named by "Who"; showing "From" too would just
            // repeat it. For a user action, "From" distinguishes in-app vs a notification.
            if !item.isSystem {
                LabeledContent("From", value: item.fromSource)
            }
            LabeledContent("Result", value: outcomeText(item.outcome))
            if item.isSystem {
                Label("A system action, not a change you made.", systemImage: "gearshape")
                    .accessibilityIdentifier("auditDetailRecovery")
            }
        }
        .navigationTitle("Change detail")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auditEventDetail")
    }
}

/// A small icon+text tag (never color-alone).
private struct TagLabel: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
    }
}

private func outcomeText(_ outcome: Outcome) -> String {
    AlarmHistoryViewModel.outcomeLabel(outcome)
}

private func outcomeIcon(_ outcome: Outcome) -> String {
    switch outcome {
    case .succeeded: "checkmark.circle"
    case .failed: "xmark.octagon"
    case .rejected: "hand.raised"
    case .noOp: "minus.circle"
    }
}

#Preview {
    NavigationStack {
        AlarmHistoryView(alarmID: AlarmID(UUID()))
    }
}
