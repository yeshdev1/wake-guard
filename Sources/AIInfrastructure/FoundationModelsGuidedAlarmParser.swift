import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// The on-device guided-generation implementation of `GuidedAlarmParsing` (WG-301). It runs a
/// `LanguageModelSession` that generates a schema-constrained `GenerableAlarmParse` (`@Generable`) — the
/// model cannot produce an off-schema value — then maps it to the pure domain `AIAlarmParse` and validates
/// bounds (defence in depth, #27). The only place FoundationModels' guided-generation API is touched, so
/// domain code never imports it. Untrusted user text is routed through the same injection framing as the
/// text path (`PromptSafety`, WG-173); no prompt or output is logged (#41). If FoundationModels is absent
/// from the SDK, it **fails closed** to `.unavailable` so the caller falls back to the text path (#33).
struct FoundationModelsGuidedAlarmParser: GuidedAlarmParsing {

    /// Schema-only instruction — guided generation supplies the field shape, so this just states the task
    /// and the disambiguation rules the deterministic step relies on. The untrusted text is delimited by
    /// `PromptSafety`, which also carries the injection preamble.
    private static let instruction = """
        Extract the alarm the user is asking for. If AM/PM is not clearly stated and 24-hour time is not \
        used, set meridiemSpecified=false and put the 1-12 clock hour in "hour". If no time is given, set \
        timeSpecified=false. Set weekdays for a repeating alarm (empty for one-time); set dayOffset only \
        for a single relative day (0=today, 1=tomorrow). Never assign criticality.
        """

    func parseAlarm(from text: String) async throws(LanguageModelError) -> AIAlarmParse {
        #if canImport(FoundationModels)
            guard case .available = SystemLanguageModel.default.availability else {
                throw .unavailable
            }
            do {
                return try await Self.generate(from: text)
            } catch let error as LanguageModelError {
                throw error
            } catch is CancellationError {
                throw .cancelled
            } catch let error as LanguageModelSession.GenerationError {
                throw Self.map(error)
            } catch {
                throw .generationFailed
            }
        #else
            throw .unavailable
        #endif
    }

    #if canImport(FoundationModels)
        /// Run the guided session and map to the validated domain DTO. Throws `LanguageModelError` for a
        /// bounds failure (`.malformedOutput`) and lets FoundationModels' own errors propagate to the
        /// caller's `catch`, which maps them.
        private static func generate(from text: String) async throws -> AIAlarmParse {
            let request = PromptSafety.request(instruction: instruction, untrusted: text)
            let session = LanguageModelSession(instructions: request.systemPrompt)
            let response = try await session.respond(
                to: request.userPrompt, generating: GenerableAlarmParse.self)
            let parse = response.content.asDomain()
            do {
                try parse.validate()
            } catch {
                throw LanguageModelError.malformedOutput
            }
            return parse
        }

        private static func map(_ error: LanguageModelSession.GenerationError) -> LanguageModelError
        {
            switch error {
            case .guardrailViolation, .refusal: .refused
            case .assetsUnavailable: .unavailable
            default: .generationFailed
            }
        }
    #endif
}

#if canImport(FoundationModels)
    /// The `@Generable` mirror of `AIAlarmParse` (WG-301) — lives here because `@Generable` is a
    /// FoundationModels macro. Constrained at generation time; mapped to the pure domain DTO for the rest of
    /// the pipeline. Carries **no criticality field** (#31), exactly like the text schema.
    @Generable
    struct GenerableAlarmParse {
        @Guide(
            description:
                "The hour the user said. If AM/PM was NOT stated, the 1-12 clock hour; else the 0-23 hour."
        )
        var hour: Int
        @Guide(description: "The minute, 0 to 59.")
        var minute: Int
        @Guide(description: "True only if the user clearly stated AM/PM or used 24-hour time.")
        var meridiemSpecified: Bool
        @Guide(description: "True if the user gave any time at all.")
        var timeSpecified: Bool
        @Guide(description: "Weekdays a repeating alarm fires; empty for a one-time alarm.")
        var weekdays: [GenerableWeekday]
        @Guide(
            description:
                "Days from today for a single relative day (0=today, 1=tomorrow); omit for weekly.")
        var dayOffset: Int?

        func asDomain() -> AIAlarmParse {
            AIAlarmParse(
                hour: hour, minute: minute, meridiemSpecified: meridiemSpecified,
                timeSpecified: timeSpecified, weekdays: Set(weekdays.map(\.asDomain)),
                dayOffset: dayOffset)
        }
    }

    /// The `@Generable` mirror of `AIWeekday`.
    @Generable
    enum GenerableWeekday: String {
        case sunday, monday, tuesday, wednesday, thursday, friday, saturday

        var asDomain: AIWeekday { AIWeekday(rawValue: rawValue) ?? .sunday }
    }
#endif
