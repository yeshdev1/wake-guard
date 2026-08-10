import Foundation

/// A **bounded** query window for upcoming events (WG-142): `[start, start + horizon]`, with the horizon
/// clamped to a sane maximum so a query can never scan an unbounded future. Wake planning only needs the
/// near future.
struct EventQueryWindow: Sendable, Equatable {
    let start: Date
    let end: Date

    /// A week ahead is plenty for wake planning.
    static let defaultHorizon: TimeInterval = 7 * 86_400
    /// Hard ceiling so a pathological horizon can't make the query unbounded.
    static let maxHorizon: TimeInterval = 30 * 86_400

    init(from start: Date, horizon: TimeInterval = defaultHorizon) {
        self.start = start
        let bounded = horizon.isFinite ? min(max(horizon, 0), Self.maxHorizon) : Self.defaultHorizon
        self.end = start.addingTimeInterval(bounded)
    }

    var isEmpty: Bool { end <= start }
}

/// Which calendars a query is scoped to (WG-142) — the user's selection. `all` = every calendar; a set
/// restricts to those identifiers, so a query is **bounded by selected calendars**.
struct CalendarSelection: Sendable, Equatable, Hashable {
    /// `nil` means "all calendars"; otherwise only these identifiers are included.
    let calendarIdentifiers: Set<String>?

    static let all = CalendarSelection(calendarIdentifiers: nil)

    static func only(_ identifiers: Set<String>) -> CalendarSelection {
        CalendarSelection(calendarIdentifiers: identifiers)
    }

    func includes(_ identifier: String) -> Bool {
        calendarIdentifiers?.contains(identifier) ?? true
    }
}

/// The **framework-independent** fields the EventKit adapter extracts from an `EKEvent` (WG-142), so the
/// mapping is testable without EventKit.
struct RawEventFields: Sendable, Equatable, Hashable {
    let id: String
    /// Absolute instants (correct regardless of the event's zone).
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let title: String
}

/// Maps `RawEventFields` to a domain `CalendarEvent` (WG-142). Pure. `start`/`end` are carried as
/// **absolute instants**; `isAllDay` is preserved (the wake calculator skips all-day events); `hasLocation`
/// is derived from a **non-empty** location string — a boolean only, never the text (#41). A malformed
/// (`end < start`) event is skipped (`nil`), never a crash.
enum CalendarEventMapping {
    static func event(from raw: RawEventFields) -> CalendarEvent? {
        guard raw.end >= raw.start else { return nil }
        return CalendarEvent(
            id: raw.id, start: raw.start, end: raw.end, isAllDay: raw.isAllDay,
            hasLocation: raw.location.map { !$0.isEmpty } ?? false, title: raw.title)
    }
}

/// Port for querying upcoming events (WG-142). The real adapter (`CalendarInfrastructure`) runs a query
/// **bounded by time and selected calendars** and maps `EKEvent` to the local `CalendarEvent`; the domain
/// stays framework-independent. It **never logs raw titles** (#41).
protocol UpcomingEventQuerying: Sendable {
    func upcomingEvents(within window: EventQueryWindow, from selection: CalendarSelection)
        async throws
        -> [CalendarEvent]
}
