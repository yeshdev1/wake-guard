import SwiftUI

/// Reads the composed environment and hosts the conversational alarm-creation flow (WG-166). Renders a safe
/// state if the environment is missing. `onCreated` reloads the alarm list once an alarm is scheduled.
struct ConversationalCreateCover: View {
    let onCreated: () -> Void
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        if let environment {
            ConversationalCreateHost(
                processor: environment.alarmCommandProcessor, clock: environment.clock,
                ids: environment.identifierGenerator,
                languageModel: environment.languageModelProvider,
                guidedParser: environment.guidedAlarmParser, onCreated: onCreated)
        } else {
            ContentUnavailableView("Unavailable", systemImage: "text.bubble")
                .accessibilityIdentifier("conversationalUnavailableEnvironment")
        }
    }
}

/// Owns the `ConversationalAlarmViewModel` in `@State` (built once from the injected ports) and presents
/// the flow. The commit closure is the **only** schedule path — it builds a `.standard` alarm from the
/// validated intent (never critical from parsed text, #31) and submits it through the command boundary.
/// The manual editor is always one tap away (#33).
private struct ConversationalCreateHost: View {
    private let processor: any AlarmCommandProcessing
    private let clock: any WallClock
    private let ids: any IdentifierGenerator
    @State private var model: ConversationalAlarmViewModel
    @State private var showingManual = false
    @Environment(\.dismiss) private var dismiss

    init(
        processor: any AlarmCommandProcessing, clock: any WallClock, ids: any IdentifierGenerator,
        languageModel: any LanguageModelProvider, guidedParser: (any GuidedAlarmParsing)?,
        onCreated: @escaping () -> Void
    ) {
        self.processor = processor
        self.clock = clock
        self.ids = ids
        let parser = NaturalLanguageAlarmParser(
            generator: StructuredGenerator(provider: languageModel), guided: guidedParser)
        _model = State(
            wrappedValue: ConversationalAlarmViewModel(
                parser: parser, clock: clock,
                commit: { spec in
                    guard
                        let alarm = ConversationalAlarmBuilder.alarm(
                            from: spec, id: ids.next(), now: clock.now)
                    else { return false }
                    switch await processor.process(
                        .create(alarm), from: .userInterface, by: .user, userConfirmed: false)
                    {
                    case .applied, .uncertain: return true  // saved locally — the alarm exists
                    default: return false
                    }
                }))
        self.onCreated = onCreated
    }

    private let onCreated: () -> Void

    var body: some View {
        NavigationStack {
            ConversationalAlarmView(model: model, onManualEditor: { showingManual = true })
                .navigationTitle("New alarm")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }.accessibilityIdentifier("conversationalClose")
                    }
                }
        }
        .onChange(of: model.stage) { _, stage in
            if case .scheduled = stage { onCreated() }  // the new alarm exists — refresh the list
        }
        .sheet(
            isPresented: $showingManual,
            onDismiss: {
                onCreated()
                dismiss()
            },
            content: { CreateAlarmView(processor: processor, clock: clock, ids: ids) }
        )
    }
}
