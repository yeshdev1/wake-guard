import Foundation

/// The structured result of reading a free-text sleep journal (WG-170): optional bedtime/wake times, a
/// coarse quality band, and a short note. **All fields are optional** (a journal may say little); an
/// unstated quality is `.unknown`, never fabricated. It carries no raw health data and no alarm authority.
struct JournalExtraction: Sendable, Equatable, Hashable {
    let bedtime: TimeOfDay?
    let wake: TimeOfDay?
    let quality: AISleepQualityBand
    let note: String?
}

/// The outcome of journal extraction (WG-170).
enum JournalExtractionOutcome: Sendable, Equatable, Hashable {
    case extracted(JournalExtraction)
    /// The model was unavailable/refused, produced unusable output, or there was nothing to extract.
    case unavailable
}

/// Deterministic, non-causal copy for surfacing journal patterns (WG-170). Any relationship between a
/// journaled factor and sleep is phrased as an **association, never a cause**, and never a medical claim
/// (#39) — so the feature can show patterns without implying causation.
enum JournalAssociationCopy {
    static let disclaimer =
        "These are associations, not causes. Alarm Agent doesn’t diagnose or give medical advice."

    /// A non-causal sentence relating a journaled factor to a sleep-quality band.
    static func association(factor: String, quality: AISleepQualityBand) -> String {
        "Nights you mentioned “\(factor)” were associated with \(quality.rawValue) sleep — "
            + "an observation, not a cause."
    }
}

/// Extracts structured fields from a free-text sleep journal (WG-170). The **raw journal stays local**: it
/// is sent only to the on-device model (WG-163 — no network), and this extractor persists, logs, and
/// transmits **nothing** — it returns only the structured `JournalExtraction`. The model maps the user's
/// words to the constrained schema (WG-161), which fails closed (unstated quality ⇒ `.unknown`,
/// out-of-range times ⇒ rejected). Any relationship the UI surfaces uses `JournalAssociationCopy` —
/// association, not causation.
struct JournalExtractor: Sendable {
    private let generator: StructuredGenerator

    init(generator: StructuredGenerator) {
        self.generator = generator
    }

    func extract(_ text: String) async -> JournalExtractionOutcome {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unavailable
        }
        do {
            let extraction = try await generator.generate(
                AIJournalExtraction.self, for: Self.request(for: text))
            return .extracted(Self.map(extraction))
        } catch {
            return .unavailable
        }
    }

    static func map(_ extraction: AIJournalExtraction) -> JournalExtraction {
        JournalExtraction(
            bedtime: Self.time(fromMinutes: extraction.bedtimeMinutesOfDay),
            wake: Self.time(fromMinutes: extraction.wakeMinutesOfDay),
            quality: extraction.quality, note: extraction.note)
    }

    private static func time(fromMinutes minutes: Int?) -> TimeOfDay? {
        guard let minutes else { return nil }
        return try? TimeOfDay(hour: minutes / 60, minute: minutes % 60)
    }

    static func request(for text: String) -> LanguageModelRequest {
        let instruction = """
            Extract structured fields from the user's sleep journal. Output JSON:
            bedtimeMinutesOfDay (Int minutes past midnight, or null),
            wakeMinutesOfDay (Int minutes past midnight, or null),
            quality (one of "poor","fair","good","unknown" — use "unknown" if not stated),
            note (a short optional summary, or null).
            Do not infer anything not stated, and do not make medical or causal claims. Output ONLY the JSON.
            """
        return PromptSafety.request(instruction: instruction, untrusted: text)
    }
}
