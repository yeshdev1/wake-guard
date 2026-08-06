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

    init(
        editing: Alarm? = nil, processor: any AlarmCommandProcessing, clock: any WallClock,
        ids: any IdentifierGenerator
    ) {
        _model = State(
            wrappedValue: CreateAlarmViewModel(
                editing: editing, processor: processor, clock: clock, ids: ids))
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

#Preview {
    let environment = AppEnvironment.preview
    CreateAlarmView(
        processor: environment.alarmCommandProcessor, clock: environment.clock,
        ids: environment.identifierGenerator)
}
