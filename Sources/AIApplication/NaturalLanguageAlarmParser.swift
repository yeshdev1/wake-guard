import Foundation

/// A non-critical, **unsaved** preview of an alarm parsed from natural language (WG-164). It is shown to
/// the user *before any save* (preview-precedes-save) and carries **no criticality** field and no alarm
/// command — a parsed draft can never be critical (#31) and cannot, by itself, schedule anything. Time is
/// a resolved 0–23 hour; `weekdays` empty ⇒ one-time (with an optional `dayOffset`).
struct AlarmDraftPreview: Sendable, Equatable, Hashable {
    let hour: Int
    let minute: Int
    let weekdays: Set<AIWeekday>
    let dayOffset: Int?

    var isWeekly: Bool { !weekdays.isEmpty }
}

/// What the user must clarify when a request is ambiguous (WG-164), always as **bounded** choices rather
/// than a silent guess.
enum AlarmClarification: Sendable, Equatable, Hashable {
    /// No time was given — ask for one.
    case missingTime
    /// AM/PM was not stated — offer both concrete interpretations to pick from.
    case meridiem(morning: AlarmDraftPreview, evening: AlarmDraftPreview)
}

/// The result of parsing a natural-language alarm request (WG-164). Either a single preview, a bounded
/// clarification, or an unavailable/unusable-model fallback to manual entry — never a saved alarm.
enum AlarmParseOutcome: Sendable, Equatable, Hashable {
    case preview(AlarmDraftPreview)
    case needsClarification(AlarmClarification)
    /// On-device intelligence isn't available on this device (off, still downloading, or unsupported) —
    /// guide the user to enable it, with manual entry as the fallback (#33). Distinct from `.notUnderstood`
    /// (WG-296): previously every failure collapsed here, so "turn it on" and "rephrase" showed identical
    /// copy and the user couldn't tell which had happened.
    case modelUnavailable
    /// The model was reachable but couldn't produce a usable alarm (a refusal or unusable output) — suggest
    /// rephrasing, with manual entry as the fallback (#33).
    case notUnderstood
}

/// Parses a natural-language alarm request into a **preview or a bounded clarification** (WG-164). The
/// model (WG-163) does the extraction; **ambiguity detection is deterministic** — a missing time or an
/// unstated AM/PM yields a clarification, never a guess. The parser holds only a `StructuredGenerator`: it
/// has **no repository, alarm manager, or policy engine**, so it cannot save or schedule — a preview
/// always precedes save, which is a later, explicit user action.
struct NaturalLanguageAlarmParser: Sendable {
    private let generator: StructuredGenerator

    init(generator: StructuredGenerator) {
        self.generator = generator
    }

    /// Parse `text`. A genuinely unavailable model routes to `.modelUnavailable`; any other failure (refusal
    /// or unusable output) routes to `.notUnderstood` (WG-296) — both offer manual entry, the deterministic
    /// fallback (#33), but the caller can now tell the user *which* happened. No raw error text is surfaced
    /// (#41): only the coarse typed case is mapped.
    func parse(_ text: String) async -> AlarmParseOutcome {
        let parse: AIAlarmParse
        do {
            parse = try await generator.generate(AIAlarmParse.self, for: Self.request(for: text))
        } catch {
            switch error {
            case .unavailable: return .modelUnavailable
            default: return .notUnderstood
            }
        }
        return Self.interpret(parse)
    }

    /// Pure, deterministic interpretation of a structured parse into an outcome. No time ⇒ ask; unstated
    /// AM/PM on a 1–12 clock hour ⇒ offer both readings; otherwise ⇒ a single preview.
    static func interpret(_ parse: AIAlarmParse) -> AlarmParseOutcome {
        guard parse.timeSpecified else { return .needsClarification(.missingTime) }
        if !parse.meridiemSpecified, (1...12).contains(parse.hour) {
            let clockHour = parse.hour
            let morningHour = clockHour == 12 ? 0 : clockHour
            let eveningHour = clockHour == 12 ? 12 : clockHour + 12
            return .needsClarification(
                .meridiem(
                    morning: draft(parse, hour: morningHour),
                    evening: draft(parse, hour: eveningHour)))
        }
        return .preview(draft(parse, hour: parse.hour))
    }

    private static func draft(_ parse: AIAlarmParse, hour: Int) -> AlarmDraftPreview {
        AlarmDraftPreview(
            hour: hour, minute: parse.minute, weekdays: parse.weekdays, dayOffset: parse.dayOffset)
    }

    /// The extraction prompt. The user's message is routed through `PromptSafety` — delimited untrusted
    /// data with an injection preamble (WG-173) — and the output is constrained to the schema (no
    /// criticality field).
    static func request(for text: String) -> LanguageModelRequest {
        let instruction = """
            Convert the user's alarm request into JSON with exactly these fields:
            hour (Int), minute (Int), meridiemSpecified (Bool), timeSpecified (Bool),
            weekdays (array of lowercase day names), dayOffset (Int or null).
            If no time is given, set timeSpecified=false.
            If AM/PM is not clearly stated and 24-hour time is not used, set meridiemSpecified=false and \
            put the 1-12 clock hour in "hour".
            weekdays lists the days a repeating alarm fires; empty for a one-time alarm.
            dayOffset is days from today (0=today, 1=tomorrow) for a one-time alarm, or null.
            Output ONLY the JSON object and no other field.
            """
        return PromptSafety.request(instruction: instruction, untrusted: text)
    }
}
