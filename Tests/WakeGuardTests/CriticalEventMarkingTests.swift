import Foundation
import XCTest

@testable import WakeGuard

/// WG-143: user-confirmed critical event marking. Verifies **the user, not the LLM, confirms
/// criticality** (the actor is always the user; there is no model path), that marking is **reversible**,
/// and that every change is **audited** as evidence.
final class CriticalEventMarkingTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private struct Fixture {
        let sut: CriticalEventMarking
        let audit: RecordingCriticalEventAudit
    }

    private func fixture() -> Fixture {
        let (store, audit) = (InMemoryCriticalEventStore(), RecordingCriticalEventAudit())
        return Fixture(sut: CriticalEventMarking(store: store, audit: audit), audit: audit)
    }

    // MARK: the user, not the LLM, confirms criticality

    func testOnlyTheUserCanBeTheActor() {
        XCTAssertEqual(
            CriticalEventActor.allCases, [.user], "criticality is user-confirmed, never a model")
    }

    func testMarkingRecordsTheUserAsActor() async throws {
        let sut = fixture().sut
        let record = try await sut.markCritical(eventID: "e1", now: now)
        XCTAssertEqual(record.actor, .user)
        XCTAssertEqual(record.action, .marked)
        XCTAssertEqual(record.eventID, "e1")
        XCTAssertEqual(record.at, now)
    }

    // MARK: reversible

    func testMarkingIsReversible() async throws {
        let sut = fixture().sut
        try await sut.markCritical(eventID: "e1", now: now)
        var marked = try await sut.isCritical(eventID: "e1")
        XCTAssertTrue(marked)

        try await sut.unmarkCritical(eventID: "e1", now: now)
        marked = try await sut.isCritical(eventID: "e1")
        XCTAssertFalse(marked, "criticality can be reversed")
    }

    func testAnUnmarkedEventIsNotCritical() async throws {
        let sut = fixture().sut
        let marked = try await sut.isCritical(eventID: "never-marked")
        XCTAssertFalse(marked)
    }

    // MARK: evidence is audited

    func testEveryChangeIsAudited() async throws {
        let fix = fixture()
        let sut = fix.sut
        try await sut.markCritical(eventID: "e1", now: now)
        try await sut.unmarkCritical(eventID: "e1", now: now.addingTimeInterval(60))
        try await sut.markCritical(eventID: "e1", now: now.addingTimeInterval(120))
        let records = await fix.audit.records
        XCTAssertEqual(records.map(\.action), [.marked, .unmarked, .marked])
        XCTAssertTrue(records.allSatisfy { $0.actor == .user && $0.eventID == "e1" })
        let stillMarked = try await sut.isCritical(eventID: "e1")
        XCTAssertTrue(stillMarked, "the final state reflects the last user action")
    }
}

private actor InMemoryCriticalEventStore: CriticalEventStore {
    private var marked: Set<String> = []
    func markedEventIDs() -> Set<String> { marked }
    func setMarked(_ isMarked: Bool, eventID: String) {
        if isMarked { marked.insert(eventID) } else { marked.remove(eventID) }
    }
}

private actor RecordingCriticalEventAudit: CriticalEventAuditing {
    private(set) var records: [CriticalEventAuditRecord] = []
    func record(_ record: CriticalEventAuditRecord) { records.append(record) }
}
