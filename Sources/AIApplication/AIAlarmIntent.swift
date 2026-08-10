import Foundation

/// A structural-constraint failure in an AI schema (WG-161) — a numeric field outside its allowed range.
/// Semantic checks (past dates, IANA zones, unsupported recurrence) are the WG-165 validator's job.
enum AISchemaError: Error, Sendable, Equatable, Hashable {
    case outOfRange(field: String)
}

/// A weekday in a parsed alarm intent (WG-161). String-raw, so an **unknown** weekday from the model
/// **fails the decode** (reject) — there is no safe default weekday (#27, fail-closed by rejection).
enum AIWeekday: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday
}

/// A specific calendar date in an alarm intent (WG-161). Bounds are checked by `validate()`.
struct AISimpleDate: Sendable, Equatable, Hashable, Codable {
    let year: Int
    let month: Int
    let day: Int

    func validate() throws {
        guard (1...12).contains(month) else { throw AISchemaError.outOfRange(field: "month") }
        guard (1...31).contains(day) else { throw AISchemaError.outOfRange(field: "day") }
    }
}

/// How an alarm recurs, in a parsed intent (WG-161). Non-empty `weekdays` ⇒ a weekly alarm; empty ⇒ a
/// one-time alarm (with an optional specific `date`). Avoids a tagged-union so model JSON decodes cleanly.
struct AIRecurrence: Sendable, Equatable, Hashable, Codable {
    let weekdays: Set<AIWeekday>
    let date: AISimpleDate?

    var isWeekly: Bool { !weekdays.isEmpty }

    func validate() throws { try date?.validate() }
}

/// A **parsed alarm intent** (WG-161) — the model's structured proposal for an alarm. It carries **no
/// criticality** (#31: only the user/policy sets criticality, never a model) and no direct alarm command;
/// it is decoded (WG-163), then the deterministic validator (WG-165) turns a *valid* intent into a
/// proposal that `AlarmPolicyEngine` may authorize. Numeric bounds are enforced by `validate()`; unknown
/// JSON keys are ignored by the synthesized decode (so a hallucinated/injected extra field is inert).
struct AIAlarmIntent: Sendable, Equatable, Hashable, Codable {
    let hour: Int
    let minute: Int
    let recurrence: AIRecurrence
    let label: String?

    static let hourRange = 0...23
    static let minuteRange = 0...59

    func validate() throws {
        guard Self.hourRange.contains(hour) else { throw AISchemaError.outOfRange(field: "hour") }
        guard Self.minuteRange.contains(minute) else {
            throw AISchemaError.outOfRange(field: "minute")
        }
        try recurrence.validate()
    }
}
