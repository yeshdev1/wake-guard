import Foundation
import XCTest

@testable import WakeGuard

/// WG-164: the natural-language alarm parser. Verifies **ambiguous requests produce bounded clarification**
/// (missing time / unstated AM/PM), that unambiguous requests yield an **unsaved preview**, that the
/// **parser can never create critical status** (no criticality field on the parse or the draft), and — as
/// a structural pin of *preview precedes save* — that the parser holds no save/schedule capability.
final class NaturalLanguageAlarmParserTests: XCTestCase {

    private func parser(_ output: String) -> NaturalLanguageAlarmParser {
        NaturalLanguageAlarmParser(
            generator: StructuredGenerator(
                provider: ScriptedLanguageModelProvider.returning(output)))
    }

    private func parse(
        hour: Int, minute: Int = 0, meridiemSpecified: Bool = true, timeSpecified: Bool = true,
        weekdays: Set<AIWeekday> = [], dayOffset: Int? = nil
    ) -> AIAlarmParse {
        AIAlarmParse(
            hour: hour, minute: minute, meridiemSpecified: meridiemSpecified,
            timeSpecified: timeSpecified, weekdays: weekdays, dayOffset: dayOffset)
    }

    // MARK: unambiguous ⇒ preview

    func testUnambiguousRequestYieldsAPreview() async {
        let json = #"""
            {"hour":7,"minute":30,"meridiemSpecified":true,"timeSpecified":true,
             "weekdays":["monday","tuesday"],"dayOffset":null}
            """#
        let outcome = await parser(json).parse("weekdays at 07:30")
        guard case .preview(let draft) = outcome else {
            return XCTFail("expected preview: \(outcome)")
        }
        XCTAssertEqual(draft.hour, 7)
        XCTAssertEqual(draft.minute, 30)
        XCTAssertEqual(draft.weekdays, [.monday, .tuesday])
        XCTAssertTrue(draft.isWeekly)
    }

    // MARK: ambiguity ⇒ bounded clarification

    func testUnstatedMeridiemOffersBothReadings() {
        guard
            case .needsClarification(.meridiem(let morning, let evening)) =
                NaturalLanguageAlarmParser.interpret(parse(hour: 8, meridiemSpecified: false))
        else { return XCTFail("expected meridiem clarification") }
        XCTAssertEqual(morning.hour, 8)
        XCTAssertEqual(evening.hour, 20)
    }

    func testTwelveOClockDisambiguatesToMidnightOrNoon() {
        guard
            case .needsClarification(.meridiem(let morning, let evening)) =
                NaturalLanguageAlarmParser.interpret(parse(hour: 12, meridiemSpecified: false))
        else { return XCTFail("expected meridiem clarification") }
        XCTAssertEqual(morning.hour, 0)
        XCTAssertEqual(evening.hour, 12)
    }

    func testMissingTimeAsksForATime() {
        let outcome = NaturalLanguageAlarmParser.interpret(
            parse(hour: 0, timeSpecified: false))
        XCTAssertEqual(outcome, .needsClarification(.missingTime))
    }

    func testStated24HourTimeIsNotTreatedAsAmbiguous() {
        // meridiemSpecified=true (24h) with hour 20 must not offer AM/PM — it is already resolved.
        guard
            case .preview(let draft) =
                NaturalLanguageAlarmParser.interpret(parse(hour: 20, meridiemSpecified: true))
        else { return XCTFail("expected preview") }
        XCTAssertEqual(draft.hour, 20)
    }

    // MARK: model failure ⇒ manual-entry fallback

    func testModelRefusalRoutesToNotUnderstood() async {
        // WG-296: a refusal is a reachable-but-unusable model, distinct from unavailable.
        let generator = StructuredGenerator(
            provider: ScriptedLanguageModelProvider.failing(.refused))
        let outcome = await NaturalLanguageAlarmParser(generator: generator).parse("at 7")
        XCTAssertEqual(outcome, .notUnderstood)
    }

    func testUnavailableModelRoutesToModelUnavailable() async {
        // WG-296: only a genuinely unavailable model gets the "turn it on" route.
        let generator = StructuredGenerator(
            provider: ScriptedLanguageModelProvider.failing(.unavailable))
        let outcome = await NaturalLanguageAlarmParser(generator: generator).parse("at 7")
        XCTAssertEqual(outcome, .modelUnavailable)
    }

    func testMalformedOutputRoutesToNotUnderstood() async {
        // Truly unparseable output (no balanced object) → the model ran but produced nothing usable.
        let outcome = await parser("not json <<< }{").parse("at 7")
        XCTAssertEqual(outcome, .notUnderstood)
    }

    // MARK: the parser can never create critical status (#31)

    func testNeitherParseNorDraftHasCriticality() {
        let parseFields = Set(Mirror(reflecting: parse(hour: 7)).children.compactMap(\.label))
        XCTAssertFalse(parseFields.contains("criticality"))

        let draft = AlarmDraftPreview(hour: 7, minute: 0, weekdays: [], dayOffset: 1)
        let draftFields = Set(Mirror(reflecting: draft).children.compactMap(\.label))
        XCTAssertEqual(draftFields, ["hour", "minute", "weekdays", "dayOffset"])
        for forbidden in ["criticality", "isCritical", "command"] {
            XCTAssertFalse(draftFields.contains(forbidden))
        }
    }

    // MARK: preview precedes save — the parser has no save/schedule capability

    func testParserSourceHasNoSaveOrScheduleCapability() throws {
        let source = try strippedParserSource()
        for token in [
            "AlarmManager", "Repository", "PolicyEngine", "AlarmCommand", ".schedule", ".save",
            ".cancel", "persist",
        ] {
            XCTAssertFalse(
                source.contains(token),
                "parser references '\(token)' — it must only produce a preview, never save/schedule"
            )
        }
    }

    private func strippedParserSource() throws -> String {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AIApplication/NaturalLanguageAlarmParser.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)
        var result = ""
        for raw in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") {
                continue
            }
            if let comment = line.range(of: "//") {
                result += line[line.startIndex..<comment.lowerBound] + "\n"
            } else {
                result += line + "\n"
            }
        }
        return result
    }
}
