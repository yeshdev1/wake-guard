import SwiftUI

/// The create-alarm form (WG-042), presented as a sheet. Lets the user build any MVP
/// schedule type (weekly or one-time), previews the next occurrence live, and only enables
/// Save when the alarm can actually ring — an unsafe/invalid date can't be saved. Submits
/// through the command processor (never persistence directly).
struct CreateAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CreateAlarmViewModel
    @State private var errorMessage: String?
    @State private var confirmationReason: String?
    private let feedbackStore: (any PreAlarmFeedbackStore)?

    init(
        editing: Alarm? = nil, processor: any AlarmCommandProcessing, clock: any WallClock,
        ids: any IdentifierGenerator, feedbackStore: (any PreAlarmFeedbackStore)? = nil
    ) {
        _model = State(
            wrappedValue: CreateAlarmViewModel(
                editing: editing, processor: processor, clock: clock, ids: ids))
        self.feedbackStore = feedbackStore
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Alarm", text: $model.label)
                        .accessibilityLabel("Alarm name")
                        .accessibilityIdentifier("alarmLabelField")
                }
                Section("Schedule") {
                    Picker("Repeats", selection: $model.kind) {
                        Text("Weekly").tag(CreateAlarmViewModel.ScheduleKind.weekly)
                        Text("Once").tag(CreateAlarmViewModel.ScheduleKind.oneTime)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("scheduleKindPicker")

                    DatePicker("Time", selection: $model.time, displayedComponents: .hourAndMinute)

                    switch model.kind {
                    case .weekly:
                        WeekdayPicker(selection: $model.weekdays)
                    case .oneTime:
                        DatePicker(
                            "Date", selection: $model.date, in: Date()...,
                            displayedComponents: .date)
                    }
                }
                Section {
                    Toggle("Critical alarm", isOn: $model.isCritical)
                        .accessibilityIdentifier("criticalAlarmToggle")
                        .accessibilityHint(
                            "Designed to ring through silent, Focus, and Do Not Disturb. Turning "
                                + "it off or changing it later needs confirmation.")
                } footer: {
                    // "Designed to" (not "rings"): the ring-through-silent guarantee is AlarmKit
                    // baseline that activates once scheduling is wired (WG-025/031) — the interim
                    // adapter doesn't ring yet. The confirm-to-change clause is true today.
                    Text(
                        "A critical alarm is designed to ring even when your phone is on silent, "
                            + "in Focus, or Do Not Disturb. It can’t be turned off or changed "
                            + "without confirming.")
                }
                ChallengeSection(challenge: $model.challenge)
                TravelSection(
                    travel: $model.travel, zoneID: model.anchorZoneID,
                    timeText: model.time.formatted(date: .omitted, time: .shortened))
                PreAlarmSection(preAlarm: $model.preAlarm, isCritical: model.isCritical)
                if let alarmID = model.editingAlarmID {
                    Section {
                        NavigationLink("History") { AlarmHistoryView(alarmID: alarmID) }
                            .accessibilityIdentifier("alarmHistoryLink")
                    } footer: {
                        Text("Who changed this alarm and when — including any automatic recovery.")
                    }
                }
                if model.editingAlarmID != nil, model.preAlarm.isEnabled, let feedbackStore {
                    PreAlarmFeedbackSection(store: feedbackStore)
                }
                Section {
                    NextOccurrenceRow(date: model.nextOccurrence)
                }
            }
            .navigationTitle(model.isEditing ? "Edit Alarm" : "New Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!model.canSave || model.isSaving)
                        .accessibilityHint(
                            model.canSave ? "" : "Pick a future time and at least one day first"
                        )
                        .accessibilityIdentifier("saveAlarmButton")
                }
            }
            .alert("Couldn’t save alarm", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Confirm change", isPresented: confirmationPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Confirm", role: .destructive) { Task { await save(confirmed: true) } }
            } message: {
                Text(confirmationReason ?? "")
            }
        }
    }

    private func save(confirmed: Bool = false) async {
        switch await model.save(confirmed: confirmed) {
        case .created:
            dismiss()
        case .invalid:
            errorMessage = "This alarm can’t ring yet — choose a future time and at least one day."
        case .needsConfirmation(let reason):
            confirmationReason = reason
        case .failed(let reason):
            errorMessage = reason
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(get: { confirmationReason != nil }, set: { if !$0 { confirmationReason = nil } })
    }
}

/// A row of weekday chips. Each chip toggles its day in the selection and exposes a full
/// day name + selected state to VoiceOver (the single-letter label alone is ambiguous).
private struct WeekdayPicker: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        // A wrapping grid (not a fixed 7-column HStack) so the chips reflow instead of
        // clipping at large Dynamic Type; each is at least a 44pt touch target.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 44), spacing: DesignSystem.Spacing.xs)],
            spacing: DesignSystem.Spacing.xs
        ) {
            ForEach(Weekday.allCases, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(Self.letter(day))
                        .font(DesignSystem.Typography.caption.weight(isOn ? .bold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            isOn
                                ? DesignSystem.Colors.accent.opacity(0.2)
                                : DesignSystem.Colors.surface,
                            in: Capsule()
                        )
                        .overlay(
                            // A non-color selected cue (a border + bold) so selection survives
                            // grayscale / Increase Contrast, never conveyed by tint alone.
                            Capsule().strokeBorder(
                                isOn ? DesignSystem.Colors.accent : .clear, lineWidth: 2)
                        )
                        .foregroundStyle(
                            isOn ? DesignSystem.Colors.accent : DesignSystem.Colors.primaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.name(day))
                .accessibilityValue(isOn ? "Selected" : "Not selected")
                .accessibilityAddTraits(.isToggle)
                .accessibilityIdentifier("weekday-\(day.rawValue)")
            }
        }
    }

    private static func name(_ day: Weekday) -> String {
        switch day {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    private static func letter(_ day: Weekday) -> String { String(name(day).prefix(1)) }
}

/// The live next-occurrence preview. When the form can't ring (past one-time / no days) it
/// says so, in the attention color plus text, so it isn't conveyed by color alone.
private struct NextOccurrenceRow: View {
    let date: Date?

    var body: some View {
        HStack {
            Text("Next")
            Spacer()
            if let date {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            } else {
                Text("Won’t ring — pick a future time")
                    .foregroundStyle(DesignSystem.Colors.statusAttention)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("nextOccurrencePreview")
    }
}

/// The wake-challenge configuration (WG-045). Choose no challenge or a walk challenge; when
/// walking, the duration and minimum steps are bounded steppers (so thresholds stay within
/// the domain's validated bounds), the accessible alternative is always offered, and the
/// footer discloses the phone-carry requirement.
private struct ChallengeSection: View {
    @Binding var challenge: ChallengeDraft

    var body: some View {
        Section {
            Picker("Wake challenge", selection: $challenge.kind) {
                Text("None").tag(ChallengeDraft.Kind.none)
                Text("Walk").tag(ChallengeDraft.Kind.walk)
            }
            .accessibilityIdentifier("challengeKindPicker")

            if challenge.kind == .walk {
                Stepper(
                    "Walk for \(challenge.durationSeconds) seconds",
                    value: $challenge.durationSeconds, in: ChallengeDraft.durationRange, step: 5
                )
                .accessibilityIdentifier("challengeDurationStepper")
                .accessibilityLabel("Walk duration")
                .accessibilityValue("\(challenge.durationSeconds) seconds")
                // Keep the required cadence (steps ÷ duration) in the plausible-walk band when
                // the duration changes, so the step count can't strand or trivialize the walk.
                .onChange(of: challenge.durationSeconds) { challenge.normalizeSteps() }
                Stepper(
                    "At least \(challenge.minimumSteps) steps",
                    value: $challenge.minimumSteps,
                    in: ChallengeDraft.stepsBounds(forDuration: challenge.durationSeconds)
                )
                .accessibilityIdentifier("challengeStepsStepper")
                .accessibilityLabel("Minimum steps")
                .accessibilityValue("\(challenge.minimumSteps) steps")
                Picker("If you can’t walk", selection: $challenge.accessibleFallback) {
                    Text("Tap a sequence").tag(AccessibleChallenge.tapSequence)
                    Text("Press and hold").tag(AccessibleChallenge.pressAndHold)
                }
                .accessibilityIdentifier("accessibleFallbackPicker")
            }
        } header: {
            Text("Wake challenge")
        } footer: {
            Text(footerText)
        }
    }

    private var footerText: String {
        challenge.kind == .walk
            ? "You’ll need to carry your phone and walk to turn the alarm off. If you can’t walk "
                + "or carry your phone, use the alternative above — it’s always available."
            : "Turn the alarm off with a tap. Add a walk challenge to make waking more deliberate."
    }
}

/// The travel-behavior configuration (WG-046). Picks how the alarm's time zone behaves when the
/// device travels, shows the anchor IANA zone accessibly, and previews the destination behavior.
/// No option shifts a schedule silently (#16); the copy never implies location tracking.
private struct TravelSection: View {
    @Binding var travel: TravelOption
    let zoneID: String
    let timeText: String

    var body: some View {
        Section {
            Picker("When traveling", selection: $travel) {
                ForEach(TravelOption.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .accessibilityIdentifier("travelBehaviorPicker")

            LabeledContent("Anchored to", value: readableZone)
                .accessibilityLabel("Anchored to time zone")
                .accessibilityValue(spokenZone)
                .accessibilityIdentifier("travelAnchorZone")
        } header: {
            Text("When you travel")
        } footer: {
            Text(travel.destinationDescription(timeText: timeText, zone: readableZone))
        }
    }

    /// The IANA identifier made human-readable (underscores → spaces), e.g. "America/New York".
    private var readableZone: String {
        zoneID.replacingOccurrences(of: "_", with: " ")
    }

    /// A VoiceOver-friendly reading of the identifier, e.g. "America, New York".
    private var spokenZone: String {
        readableZone.replacingOccurrences(of: "/", with: ", ")
    }
}

/// The smart-pre-alarm configuration (WG-047, PRODUCT_SPEC §3.3). Enables a gentle pre-wake
/// prompt, sets its bounded lead-time window, and lets the user choose which actions the prompt
/// offers. The footer always states the #7 guarantee (no response → the alarm is unchanged) and,
/// for a critical alarm, that turning it off from the prompt needs confirmation.
private struct PreAlarmSection: View {
    @Binding var preAlarm: PreAlarmDraft
    let isCritical: Bool

    var body: some View {
        Section {
            Toggle("Check before the alarm", isOn: $preAlarm.isEnabled)
                .accessibilityIdentifier("preAlarmToggle")
            if preAlarm.isEnabled {
                Stepper(
                    "Check \(preAlarm.leadTimeMinutes) minutes early",
                    value: $preAlarm.leadTimeMinutes, in: PreAlarmDraft.leadRange, step: 5
                )
                .accessibilityIdentifier("preAlarmLeadStepper")
                .accessibilityLabel("Pre-alarm window")
                .accessibilityValue("\(preAlarm.leadTimeMinutes) minutes before")

                ForEach(PreAlarmAction.allCases, id: \.self) { action in
                    Toggle(Self.actionTitle(action), isOn: binding(for: action))
                        .accessibilityHint("Adds this option to the pre-alarm prompt")
                        .accessibilityIdentifier("preAlarmAction-\(action.rawValue)")
                }
            }
        } header: {
            Text("Smart pre-alarm")
        } footer: {
            if preAlarm.isEnabled {
                Text(
                    PreAlarmDraft.promptDisclosure(
                        isCritical: isCritical, offersActions: !preAlarm.allowedActions.isEmpty))
            } else {
                Text(
                    "A gentle check before the alarm if you already seem awake. You choose what "
                        + "the prompt can do; ignoring it always keeps your alarm.")
            }
        }
    }

    private func binding(for action: PreAlarmAction) -> Binding<Bool> {
        Binding(
            get: { preAlarm.allowedActions.contains(action) },
            set: { isOn in
                if isOn {
                    preAlarm.allowedActions.insert(action)
                } else {
                    preAlarm.allowedActions.remove(action)
                }
            })
    }

    private static func actionTitle(_ action: PreAlarmAction) -> String {
        switch action {
        case .turnOffToday: "Offer “Turn off today”"
        case .changeTime: "Offer “Change time”"
        case .remindLater: "Offer “Remind later”"
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview
    CreateAlarmView(
        processor: environment.alarmCommandProcessor, clock: environment.clock,
        ids: environment.identifierGenerator)
}
