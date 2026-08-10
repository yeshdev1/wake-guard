import Foundation
import XCTest

@testable import WakeGuard

/// WG-176: the AI hallucination + safety evaluation. Runs the WG-175 corpus through the deterministic
/// pipeline and verifies the **invalid-schedule rate and unsupported-claim rate are measured** (and, for
/// the deterministic core, zero), that **all alarm mutations remain policy-controlled** (critical cases
/// require confirmation; the evaluator performs no mutation), and that **failures produce backlog fixes**.
final class SafetyEvaluationTests: XCTestCase {

    private func now() throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        return try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 6, minute: 0)))
    }

    // MARK: rates are measured and (deterministically) zero

    func testCorpusHasZeroInvalidScheduleAndUnsupportedClaimRate() throws {
        let report = try SafetyEvaluator.evaluate(EvaluationCorpus.cases, now: try now())
        XCTAssertEqual(report.invalidScheduleRate, 0, "an invalid schedule slipped through")
        XCTAssertEqual(report.unsupportedClaimRate, 0, "an unsupported claim survived")
        XCTAssertGreaterThan(report.scheduleCaseCount, 0, "expected schedule cases to be measured")
        XCTAssertGreaterThan(
            report.groundingCaseCount, 0, "expected grounding cases to be measured")
    }

    func testEveryCorpusCaseMatchesItsExpectation() throws {
        let report = try SafetyEvaluator.evaluate(EvaluationCorpus.cases, now: try now())
        XCTAssertTrue(
            report.failures.isEmpty,
            "eval failures (each a backlog fix):\n" + report.backlog.joined(separator: "\n"))
    }

    // MARK: all alarm mutations remain policy-controlled

    func testEveryCriticalCaseRequiresConfirmation() throws {
        for evalCase in EvaluationCorpus.cases where evalCase.category == .criticalEvent {
            let actual = try SafetyEvaluator.actualResult(for: evalCase, now: try now())
            XCTAssertEqual(
                actual, .requiresConfirmation,
                "critical case \(evalCase.id) must require confirmation, never apply silently")
        }
    }

    func testEvaluatorPerformsNoAlarmMutation() throws {
        // The evaluator calls only pure functions — a source-scan pins it never reaches a command
        // processor, repository, or AlarmKit, so running the evaluation cannot change an alarm.
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/TestSupport/SafetyEvaluator.swift")
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
        for forbidden in [
            "AlarmCommandProcessing", "Repository", "AlarmManager", ".process(", "AlarmKit",
        ] {
            XCTAssertFalse(
                code.contains(forbidden),
                "the evaluator references '\(forbidden)' — it must not mutate")
        }
    }

    // MARK: failures produce backlog fixes

    func testAMislabeledCaseIsReportedAsABacklogItem() throws {
        // A deliberately-wrong expectation (an ambiguous parse expected to `allow`) must surface as a
        // failure with a ready-to-file backlog line — the mechanism that turns a regression into a fix.
        let mislabeled = EvaluationCase(
            id: "bad-1", category: .ambiguousDate,
            input: .alarmParse(
                AIAlarmParse(
                    hour: 8, minute: 0, meridiemSpecified: false, timeSpecified: true, weekdays: [],
                    dayOffset: nil)),
            expected: .allow, note: "deliberately wrong")
        let report = try SafetyEvaluator.evaluate([mislabeled], now: try now())
        XCTAssertEqual(report.failures.count, 1)
        let backlogLine = try XCTUnwrap(report.backlog.first)
        XCTAssertTrue(backlogLine.contains("bad-1"))
        XCTAssertTrue(backlogLine.contains("expected allow"))
    }
}
