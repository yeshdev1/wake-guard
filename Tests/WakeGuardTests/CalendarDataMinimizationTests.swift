import Foundation
import XCTest

@testable import WakeGuard

/// WG-140: calendar data minimization + redaction. Verifies **only wake-planning fields are retained**,
/// that **titles/notes remain local** (the title is `localOnly`, notes aren't kept at all), and that
/// **model-facing summaries are redacted** — the `RedactedEventSummary` structurally carries no title,
/// notes, or location text, so a malicious event title can never reach a model (#28/#35).
final class CalendarDataMinimizationTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(title: String, hasLocation: Bool = true) -> CalendarEvent {
        CalendarEvent(
            id: "evt-1", start: start, end: start.addingTimeInterval(3_600), isAllDay: false,
            hasLocation: hasLocation, title: title)
    }

    // MARK: only wake-planning fields are retained

    func testPlanRetainsOnlyTheWakePlanningFields() {
        XCTAssertEqual(
            CalendarDataMinimizationPlan.retainedFields,
            [.start, .end, .isAllDay, .hasLocation, .title])
        for rule in CalendarDataMinimizationPlan.retained {
            XCTAssertFalse(rule.purpose.isEmpty, "\(rule.field) needs a purpose")
        }
        let fields = CalendarDataMinimizationPlan.retained.map(\.field)
        XCTAssertEqual(Set(fields).count, fields.count, "no duplicate field rules")
    }

    // MARK: titles/notes remain local

    func testTitleIsLocalOnlyAndPlanningFieldsAreModelSafe() {
        XCTAssertEqual(CalendarDataMinimizationPlan.localOnlyFields, [.title])
        XCTAssertEqual(
            CalendarDataMinimizationPlan.modelSafeFields, [.start, .end, .isAllDay, .hasLocation])
    }

    func testCalendarEventRetainsNoNotesField() {
        // Notes are not retained at all — the local model's fields are the minimal planning set + title.
        let mirror = Mirror(reflecting: event(title: "x"))
        XCTAssertEqual(
            Set(mirror.children.compactMap(\.label)),
            ["id", "start", "end", "isAllDay", "hasLocation", "title"])
    }

    // MARK: model-facing summaries are redacted

    func testRedactedSummaryOmitsTitleNotesAndLocationText() {
        let mirror = Mirror(reflecting: CalendarRedaction.summary(of: event(title: "x")))
        XCTAssertEqual(
            Set(mirror.children.compactMap(\.label)),
            ["start", "end", "isAllDay", "hasLocation", "isConfirmedImportant"])
    }

    func testRedactionPreservesCoarsePlanningFields() {
        let summary = CalendarRedaction.summary(of: event(title: "x"), isConfirmedImportant: true)
        XCTAssertEqual(summary.start, start)
        XCTAssertEqual(summary.end, start.addingTimeInterval(3_600))
        XCTAssertFalse(summary.isAllDay)
        XCTAssertTrue(summary.hasLocation)
        XCTAssertTrue(summary.isConfirmedImportant)
    }

    func testRedactedSummaryNeverContainsTheTitleText() throws {
        // The strongest pin: encode the model-facing summary and confirm none of the (sensitive) title
        // survives — a title can't leak to a model through the summary.
        let summary = CalendarRedaction.summary(
            of: event(title: "Confidential Oncology Appointment"))
        let data = try JSONEncoder().encode(summary)
        let json = try XCTUnwrap(String(bytes: data, encoding: .utf8)).lowercased()
        for word in ["confidential", "oncology", "appointment"] {
            XCTAssertFalse(json.contains(word), "the title must not survive redaction: \(word)")
        }
    }

    func testTheRedactedSummaryCarriesExactlyThePlansModelSafeFields() {
        // Structural alignment: the summary's fields = the plan's modelSafe fields (+ the importance
        // flag) — every modelSafe field is present and no localOnly field (title) is.
        let mirror = Mirror(reflecting: CalendarRedaction.summary(of: event(title: "x")))
        let summaryFields = Set(mirror.children.compactMap(\.label))
        let modelSafe = Set(CalendarDataMinimizationPlan.modelSafeFields.map(\.rawValue))
        XCTAssertEqual(summaryFields.subtracting(["isConfirmedImportant"]), modelSafe)
        XCTAssertFalse(summaryFields.contains("title"), "no local-only field reaches the summary")
    }
}
