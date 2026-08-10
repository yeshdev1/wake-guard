import EventKit
import Foundation

/// Queries upcoming events from `EKEventStore` (device-only, WG-142). The query is **bounded by time**
/// (`EventQueryWindow`) and **by the selected calendars**, and each `EKEvent` is mapped to the local
/// `CalendarEvent` via the pure `CalendarEventMapping` (so all-day / time-zone handling is tested
/// framework-free). Titles are carried into the local model but are **never logged** — this adapter emits
/// no logs at all (#41). `@unchecked Sendable`: `EKEventStore` is documented thread-safe and the only
/// stored state.
struct EventKitUpcomingEventAdapter: UpcomingEventQuerying, @unchecked Sendable {
    private let store = EKEventStore()

    func upcomingEvents(within window: EventQueryWindow, from selection: CalendarSelection)
        async throws
        -> [CalendarEvent]
    {
        guard !window.isEmpty else { return [] }
        try Task.checkCancellation()

        // A selection that matches no calendar returns no events (an empty predicate list is ambiguous).
        let calendars = selectedCalendars(selection)
        if let calendars, calendars.isEmpty { return [] }
        let predicate = store.predicateForEvents(
            withStart: window.start, end: window.end, calendars: calendars)

        return store.events(matching: predicate).compactMap { event in
            CalendarEventMapping.event(
                from: RawEventFields(
                    id: event.eventIdentifier ?? event.calendarItemIdentifier,
                    start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                    location: event.location, title: event.title ?? ""))
        }
    }

    /// The `EKCalendar`s matching the selection, or `nil` for all calendars.
    private func selectedCalendars(_ selection: CalendarSelection) -> [EKCalendar]? {
        guard let identifiers = selection.calendarIdentifiers else { return nil }
        return store.calendars(for: .event).filter { identifiers.contains($0.calendarIdentifier) }
    }
}
