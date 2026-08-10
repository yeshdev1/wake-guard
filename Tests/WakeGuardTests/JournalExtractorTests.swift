import Foundation
import XCTest

@testable import WakeGuard

/// WG-170: conversational sleep-journal extraction. Verifies **user text maps to structured optional
/// fields** (unstated fields stay `nil`/`.unknown`, never fabricated), that any surfaced relationship is an
/// **association, not a causation**, and — as a locality pin of *the original journal remains local* — that
/// the extractor references no network / persistence / logging sink.
final class JournalExtractorTests: XCTestCase {

    private func extractor(_ output: String) -> JournalExtractor {
        JournalExtractor(
            generator: StructuredGenerator(
                provider: ScriptedLanguageModelProvider.returning(output)))
    }

    // MARK: user text maps to structured optional fields

    func testFullJournalMapsToAllFields() async throws {
        let json = #"""
            {"bedtimeMinutesOfDay":1380,"wakeMinutesOfDay":420,"quality":"good","note":"Felt rested."}
            """#
        guard
            case .extracted(let extraction) = await extractor(json).extract(
                "slept 11pm to 7am, great")
        else { return XCTFail("expected extraction") }
        XCTAssertEqual(extraction.bedtime, try TimeOfDay(hour: 23, minute: 0))
        XCTAssertEqual(extraction.wake, try TimeOfDay(hour: 7, minute: 0))
        XCTAssertEqual(extraction.quality, .good)
        XCTAssertEqual(extraction.note, "Felt rested.")
    }

    func testSparseJournalLeavesFieldsOptional() async {
        let json =
            #"{"bedtimeMinutesOfDay":null,"wakeMinutesOfDay":null,"quality":"unknown","note":null}"#
        guard case .extracted(let extraction) = await extractor(json).extract("not sure, tired")
        else { return XCTFail("expected extraction") }
        XCTAssertNil(extraction.bedtime)
        XCTAssertNil(extraction.wake)
        XCTAssertEqual(extraction.quality, .unknown)
        XCTAssertNil(extraction.note)
    }

    func testUnknownQualityFailsClosed() async {
        let json =
            #"{"bedtimeMinutesOfDay":null,"wakeMinutesOfDay":null,"quality":"stellar","note":null}"#
        guard case .extracted(let extraction) = await extractor(json).extract("x") else {
            return XCTFail("expected extraction")
        }
        XCTAssertEqual(extraction.quality, .unknown)
    }

    // MARK: fail-closed / fallback

    func testOutOfRangeMinutesAreRejected() async {
        let json =
            #"{"bedtimeMinutesOfDay":1440,"wakeMinutesOfDay":null,"quality":"good","note":null}"#
        let outcome = await extractor(json).extract("x")
        XCTAssertEqual(outcome, .unavailable)
    }

    func testModelUnavailableYieldsUnavailable() async {
        let failing = JournalExtractor(
            generator: StructuredGenerator(
                provider: ScriptedLanguageModelProvider.failing(.refused)))
        let outcome = await failing.extract("slept fine")
        XCTAssertEqual(outcome, .unavailable)
    }

    func testEmptyTextYieldsUnavailable() async {
        let outcome = await extractor(#"{"quality":"good"}"#).extract("   ")
        XCTAssertEqual(outcome, .unavailable)
    }

    // MARK: associations are not called causation

    func testAssociationCopyIsNeverCausal() {
        let samples = [
            JournalAssociationCopy.disclaimer,
            JournalAssociationCopy.association(factor: "coffee", quality: .poor),
            JournalAssociationCopy.association(factor: "exercise", quality: .good),
        ]
        for text in samples {
            let lower = text.lowercased()
            XCTAssertTrue(
                lower.contains("associat") || lower.contains("not a cause"),
                "copy must frame as association: \(text)")
            for causal in ["causes ", "because", "leads to", "makes you", "due to"] {
                XCTAssertFalse(lower.contains(causal), "copy must not imply causation: \(text)")
            }
        }
    }

    // MARK: the original journal remains local (no sink for raw text)

    func testExtractorReferencesNoNetworkPersistenceOrLoggingSink() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AIApplication/JournalExtractor.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)
        var code = ""
        for raw in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") {
                continue
            }
            if let comment = line.range(of: "//") {
                code += line[line.startIndex..<comment.lowerBound] + "\n"
            } else {
                code += line + "\n"
            }
        }
        for sink in [
            "URLSession", "URLRequest", ".write(to:", "FileHandle", "Logger", "os_log", "print(",
            "PrivacyLog", "NSLog", "UserDefaults", "fputs", "fwrite",
        ] {
            XCTAssertFalse(
                code.contains(sink),
                "\(sink) — the raw journal must stay local (no persistence/network/logging)")
        }
    }
}
