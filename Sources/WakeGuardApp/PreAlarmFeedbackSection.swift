import SwiftUI

/// Records the user's coarse pre-alarm feedback (WG-090) — "I wasn't awake" or "helpful". Advisory
/// only: it writes to an aggregate, on-device tally that holds **no alarm authority** and cannot retune
/// any behavior (#8/#31/#41). `@MainActor` because it feeds SwiftUI.
@MainActor
@Observable
final class PreAlarmFeedbackModel {
    /// The category recorded this session, if any — the view thanks the user and stops offering (a
    /// single, low-friction tap; not a running tally the user manages).
    private(set) var recorded: PreAlarmFeedbackCategory?

    private let store: any PreAlarmFeedbackStore

    init(store: any PreAlarmFeedbackStore) {
        self.store = store
    }

    func record(_ category: PreAlarmFeedbackCategory) async {
        await store.record(category)
        recorded = category
    }
}

/// A pre-alarm feedback affordance (WG-090) — shown when editing an alarm that has the pre-alarm check
/// enabled. Two low-friction taps; on-device + aggregate; the copy makes clear it never changes when an
/// alarm rings (#8). Fully VoiceOver-legible with stable identifiers; reflows at large Dynamic Type via
/// `Form`.
struct PreAlarmFeedbackSection: View {
    @State private var model: PreAlarmFeedbackModel

    init(store: any PreAlarmFeedbackStore) {
        _model = State(wrappedValue: PreAlarmFeedbackModel(store: store))
    }

    var body: some View {
        Section {
            if let recorded = model.recorded {
                Label(
                    recorded == .helpful
                        ? "Thanks — glad the pre-alarm helped."
                        : "Thanks — we’ll keep improving it.",
                    systemImage: "checkmark.circle"
                )
                .accessibilityIdentifier("preAlarmFeedbackThanks")
            } else {
                Button("The pre-alarm was helpful") { Task { await model.record(.helpful) } }
                    .accessibilityIdentifier("preAlarmFeedbackHelpful")
                Button("I wasn’t actually awake") { Task { await model.record(.notAwake) } }
                    .accessibilityIdentifier("preAlarmFeedbackNotAwake")
            }
        } header: {
            Text("Pre-alarm feedback")
        } footer: {
            Text(
                "Your feedback stays on this device and helps us improve when pre-alarm checks appear. "
                    + "It never changes when your alarms ring.")
        }
    }
}
