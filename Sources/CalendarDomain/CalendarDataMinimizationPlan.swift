import Foundation

/// A calendar field WakeGuard may retain for wake planning (WG-140). The full set is deliberately small —
/// only what the latest-safe-wake calculation (WG-145) and the user's important-event confirmation
/// (WG-143) need.
enum CalendarField: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case start
    case end
    case isAllDay
    case hasLocation
    case title
}

/// How sensitive a retained field is (WG-140). `localOnly` fields stay on the device and never reach a
/// model or the cloud (#28/#35); `modelSafe` fields are coarse, non-text values safe to summarize.
enum CalendarFieldSensitivity: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case localOnly
    case modelSafe
}

/// One entry in the calendar data-minimization plan (WG-140): a retained field, why it's kept, and its
/// sensitivity.
struct CalendarFieldRule: Sendable, Equatable, Hashable {
    let field: CalendarField
    let purpose: String
    let sensitivity: CalendarFieldSensitivity
}

/// The calendar data-minimization plan (WG-140): the **complete, minimal** set of EventKit fields
/// WakeGuard retains, each with a purpose and sensitivity. It is the single source of truth for what the
/// EventKit adapter (WG-142) maps in — nothing else is kept. The `title` is `localOnly` (shown to the
/// user, never modelled); everything else is a coarse `modelSafe` value. The model-facing
/// `RedactedEventSummary` carries **exactly** the `modelSafe` fields — so a title/notes can never be
/// summarized to a model (structural, not policy).
enum CalendarDataMinimizationPlan {
    static let retained: [CalendarFieldRule] = [
        CalendarFieldRule(
            field: .start, purpose: "Compute the latest safe wake time before the event.",
            sensitivity: .modelSafe),
        CalendarFieldRule(
            field: .end, purpose: "Estimate how long the event runs.", sensitivity: .modelSafe),
        CalendarFieldRule(
            field: .isAllDay, purpose: "Skip all-day events, which don't drive a wake time.",
            sensitivity: .modelSafe),
        CalendarFieldRule(
            field: .hasLocation,
            purpose:
                "Add a travel buffer when an event has a location — the boolean only, never the "
                + "coordinates or address.", sensitivity: .modelSafe),
        CalendarFieldRule(
            field: .title,
            purpose:
                "Show the event so you can confirm which one matters. Stays on your device; never "
                + "sent to a model.", sensitivity: .localOnly),
    ]

    static var retainedFields: Set<CalendarField> { Set(retained.map(\.field)) }

    static var modelSafeFields: Set<CalendarField> {
        Set(retained.filter { $0.sensitivity == .modelSafe }.map(\.field))
    }

    static var localOnlyFields: Set<CalendarField> {
        Set(retained.filter { $0.sensitivity == .localOnly }.map(\.field))
    }

    static func rule(for field: CalendarField) -> CalendarFieldRule? {
        retained.first { $0.field == field }
    }
}
