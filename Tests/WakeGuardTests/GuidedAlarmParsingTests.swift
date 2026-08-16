import Foundation
import XCTest

@testable import WakeGuard

/// WG-301: the guided-generation seam for the describe-alarm parse. The real on-device guided call is
/// device-only (needs an Apple-Intelligence-eligible device), so these pin the **wiring**: the parser uses
/// the guided port when present, falls back to the text path only when guided is **unavailable**, propagates
/// other guided failures, and the guided result flows through the same deterministic interpret step. The
/// text path keeps its own coverage in `StructuredGeneratorTests` / `NaturalLanguageAlarmParserTests`.
final class GuidedAlarmParsingTests: XCTestCase {

    private func textOnlyGenerator(_ json: String) -> StructuredGenerator {
        StructuredGenerator(provider: ScriptedLanguageModelProvider.returning(json))
    }

    private let weeklyJSON = #"""
        {"hour":7,"minute":30,"meridiemSpecified":true,"timeSpecified":true,"weekdays":["monday"],"dayOffset":null}
        """#

    func testGuidedResultIsUsedAndInterpretedWhenPresent() async {
        // The guided port returns a valid parse → the flow previews it, never touching the text path.
        let guided = StubGuidedParser(result: .success(sampleParse()))
        let textNeverUsed = StructuredGenerator(
            provider: ScriptedLanguageModelProvider.failing(.generationFailed))
        let parser = NaturalLanguageAlarmParser(generator: textNeverUsed, guided: guided)

        let outcome = await parser.parse("wake me at 7:30 tomorrow")

        guard case .preview = outcome else { return XCTFail("expected a preview, got \(outcome)") }
        XCTAssertEqual(guided.calls, 1)
    }

    func testGuidedUnavailableFallsBackToTheTextPath() async {
        // Guided reports unavailable (older SDK / feature absent) → the text path produces the parse.
        let guided = StubGuidedParser(result: .failure(.unavailable))
        let parser = NaturalLanguageAlarmParser(
            generator: textOnlyGenerator(weeklyJSON), guided: guided)

        let outcome = await parser.parse("mondays at 7:30")

        guard case .preview = outcome else {
            return XCTFail("the text fallback should preview, got \(outcome)")
        }
        XCTAssertEqual(guided.calls, 1, "guided was tried first")
    }

    func testGuidedRefusalPropagatesAsNotUnderstood() async {
        // A reachable-but-refusing guided model does NOT retry on the text path (same model, wasted call);
        // it routes to .notUnderstood (WG-296 distinction preserved).
        let guided = StubGuidedParser(result: .failure(.refused))
        let parser = NaturalLanguageAlarmParser(
            generator: textOnlyGenerator(weeklyJSON), guided: guided)

        let outcome = await parser.parse("mondays at 7:30")

        XCTAssertEqual(outcome, .notUnderstood)
    }

    func testNoGuidedPortUsesTheTextPathUnchanged() async {
        // Existing behaviour when no guided port is injected (tests/previews): pure text path.
        let parser = NaturalLanguageAlarmParser(generator: textOnlyGenerator(weeklyJSON))
        let outcome = await parser.parse("mondays at 7:30")
        guard case .preview = outcome else { return XCTFail("expected preview, got \(outcome)") }
    }

    // MARK: helpers

    private func sampleParse() -> AIAlarmParse {
        AIAlarmParse(
            hour: 7, minute: 30, meridiemSpecified: true, timeSpecified: true, weekdays: [],
            dayOffset: 1)
    }
}

/// A scripted `GuidedAlarmParsing` for the wiring tests — returns a parse or throws a typed failure, and
/// counts calls so a test can prove guided is tried before the text fallback.
private final class StubGuidedParser: GuidedAlarmParsing, @unchecked Sendable {
    private let result: Result<AIAlarmParse, LanguageModelError>
    private let count = Synchronized(0)
    var calls: Int { count.get() }

    init(result: Result<AIAlarmParse, LanguageModelError>) {
        self.result = result
    }

    func parseAlarm(from text: String) async throws(LanguageModelError) -> AIAlarmParse {
        count.mutate { $0 += 1 }
        switch result {
        case .success(let parse): return parse
        case .failure(let error): throw error
        }
    }
}
