import Foundation

/// A calendar event as WakeGuard keeps it **on device** (WG-140) — only the fields wake planning needs.
/// The `title` is retained **locally** so the user can recognise which event matters (WG-143), but it is
/// **untrusted content** (#28) and **never** leaves the device or reaches a model — the redacted summary
/// omits it. Notes/attendees/URLs are **not retained at all** (data minimization). `hasLocation` is a
/// boolean only — never coordinates or an address (#41).
struct CalendarEvent: Sendable, Equatable, Hashable, Identifiable {
    let id: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let hasLocation: Bool
    /// Local-only, untrusted display text (#28) — never sent to a model.
    let title: String
}

/// The **model-facing** projection of a calendar event (WG-140): only coarse, non-text planning fields.
/// It structurally cannot carry a title, notes, or a location string, so a malicious event title can
/// never reach a model (#28) and no full calendar text is ever sent off-device by default (#35).
struct RedactedEventSummary: Sendable, Equatable, Hashable, Codable {
    let start: Date
    let end: Date
    let isAllDay: Bool
    let hasLocation: Bool
    /// Whether the user confirmed this event as important (WG-143) — a boolean, not the title.
    let isConfirmedImportant: Bool
}

/// Redacts a local `CalendarEvent` down to the model-safe `RedactedEventSummary` (WG-140). The **only**
/// way calendar data reaches a model or leaves the device — and it carries no free text.
enum CalendarRedaction {
    static func summary(of event: CalendarEvent, isConfirmedImportant: Bool = false)
        -> RedactedEventSummary
    {
        RedactedEventSummary(
            start: event.start, end: event.end, isAllDay: event.isAllDay,
            hasLocation: event.hasLocation, isConfirmedImportant: isConfirmedImportant)
    }
}
