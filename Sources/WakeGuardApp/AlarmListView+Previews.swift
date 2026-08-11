import SwiftUI

// Previews for the alarm list (split out of `AlarmListView.swift` to keep that file within the length
// limit as the list grew a walk-challenge test affordance, WG-073).

extension AlarmListContent {
    /// Illustrative sample content for previews (no repository/disk). The `nextRingText`
    /// mirrors the relative form the view model produces.
    fileprivate static let preview: AlarmListContent = {
        let wake = AlarmListItem(
            id: AlarmID(UUID()), label: "Wake up", isEnabled: true, isCritical: false,
            status: .scheduled, nextOccurrence: Date(timeIntervalSince1970: 1_700_000_000),
            nextRingText: "Tomorrow, 7:00 AM",
            accessibilityLabel: "Wake up, Scheduled, Tomorrow, 7:00 AM",
            challengeRequiredSteps: 20)
        let medication = AlarmListItem(
            id: AlarmID(UUID()), label: "Medication", isEnabled: true, isCritical: true,
            status: .critical, nextOccurrence: Date(timeIntervalSince1970: 1_700_030_000),
            nextRingText: "Tomorrow, 9:00 PM",
            accessibilityLabel: "Critical alarm. Medication, Critical, Tomorrow, 9:00 PM",
            challengeRequiredSteps: nil)
        let stale = AlarmListItem(
            id: AlarmID(UUID()), label: "Old reminder", isEnabled: true, isCritical: false,
            status: .attention, nextOccurrence: nil, nextRingText: "No upcoming time",
            accessibilityLabel: "Old reminder, Needs attention, No upcoming time",
            challengeRequiredSteps: nil)
        let off = AlarmListItem(
            id: AlarmID(UUID()), label: "Weekend lie-in", isEnabled: false, isCritical: false,
            status: .off, nextOccurrence: nil, nextRingText: "Off",
            accessibilityLabel: "Weekend lie-in, Off", challengeRequiredSteps: nil)
        return AlarmListContent(nextAlarm: wake, items: [wake, medication, stale, off])
    }()
}

extension AlarmListViewModel {
    /// A preview model over the in-memory graph (no disk, no real AlarmKit).
    fileprivate static var preview: AlarmListViewModel {
        let environment = AppEnvironment.preview
        return AlarmListViewModel(
            alarms: environment.alarmRepository, clock: environment.clock,
            processor: environment.alarmCommandProcessor)
    }
}

#Preview("Loaded — light") {
    NavigationStack {
        AlarmListLoadedView(content: .preview, model: .preview, onEdit: { _ in }).navigationTitle(
            "Alarms")
    }
}

#Preview("Loaded — dark") {
    NavigationStack {
        AlarmListLoadedView(content: .preview, model: .preview, onEdit: { _ in }).navigationTitle(
            "Alarms")
    }
    .preferredColorScheme(.dark)
}

#Preview("Loaded — accessibility XL") {
    NavigationStack {
        AlarmListLoadedView(content: .preview, model: .preview, onEdit: { _ in }).navigationTitle(
            "Alarms")
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Reconciling banner") {
    VStack(spacing: 0) {
        ReconcilingBanner()
        AlarmListLoadedView(content: .preview, model: .preview, onEdit: { _ in })
    }
}

#Preview("Empty") {
    AlarmListMessageView(
        systemImage: "alarm", title: "No alarms yet",
        message: "Alarms you create will appear here.", identifier: "alarmListEmpty")
}

#Preview("Error") {
    AlarmListMessageView(
        systemImage: "exclamationmark.triangle", title: "Couldn’t load alarms",
        message: "Your alarms couldn’t be loaded. They are still saved.",
        identifier: "alarmListError")
}
