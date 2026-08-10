import Foundation
import XCTest

@testable import WakeGuard

/// WG-129: health data export/delete controls. Verifies **local derived data can be deleted**, that the
/// **HealthKit source is not represented as owned by the app** (export provenance + only derived
/// aggregates), and that **deletion is audited without retaining the deleted content** (#41/#46).
final class WellnessDataControlsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(_ offsetDays: Int, _ asleep: TimeInterval?) -> DerivedWellnessRecord {
        DerivedWellnessRecord(
            date: now.addingTimeInterval(Double(offsetDays) * 86_400), asleepDuration: asleep)
    }

    private struct Fixture {
        let sut: WellnessDataControls
        let store: InMemoryDerivedWellnessStore
        let audit: RecordingDeletionAudit
    }

    private func fixture(_ records: [DerivedWellnessRecord]) -> Fixture {
        let (store, audit) = (InMemoryDerivedWellnessStore(records), RecordingDeletionAudit())
        return Fixture(
            sut: WellnessDataControls(store: store, audit: audit), store: store, audit: audit)
    }

    // MARK: local derived data can be deleted

    func testDeleteRemovesAllLocalDerivedDataAndReturnsCount() async throws {
        let fix = fixture([record(-1, 7 * 3_600), record(-2, 6 * 3_600)])
        let receipt = try await fix.sut.deleteAllDerivedData(now: now)
        XCTAssertEqual(receipt.recordCount, 2)
        let remaining = await fix.store.records()
        XCTAssertTrue(remaining.isEmpty, "all local derived data is gone")
    }

    func testDeletingWhenEmptyIsAZeroCountButStillAudited() async throws {
        let fix = fixture([])
        let receipt = try await fix.sut.deleteAllDerivedData(now: now)
        XCTAssertEqual(receipt.recordCount, 0)
        let recorded = await fix.audit.recorded
        XCTAssertEqual(recorded.count, 1, "even a no-op delete is recorded")
    }

    // MARK: deletion is audited without retaining content

    func testDeletionIsAuditedWithActorCountAndTimestampOnly() async throws {
        let fix = fixture([record(-1, 7 * 3_600)])
        let receipt = try await fix.sut.deleteAllDerivedData(now: now, actor: .user)
        let recorded = await fix.audit.recorded
        XCTAssertEqual(recorded, [receipt])
        XCTAssertEqual(receipt.actor, .user)
        XCTAssertEqual(receipt.deletedAt, now)
    }

    func testTheDeletionReceiptRetainsNoDeletedContent() {
        // The audit record's fields are exactly {deletedAt, recordCount, actor} — no field could hold a
        // sleep value (#41/#46).
        let mirror = Mirror(
            reflecting: WellnessDeletionReceipt(deletedAt: now, recordCount: 3, actor: .user))
        XCTAssertEqual(
            Set(mirror.children.compactMap(\.label)), ["deletedAt", "recordCount", "actor"])
    }

    // MARK: HealthKit source is not represented as owned by the app

    func testExportCarriesProvenanceDisclaimingHealthKitOwnership() async throws {
        let payload = try await fixture([record(-1, 7 * 3_600)]).sut.export(now: now)
        let provenance = payload.provenance.lowercased()
        XCTAssertTrue(
            provenance.contains("wakeguard's own"), "these are the app's derived estimates")
        XCTAssertTrue(
            provenance.contains("not your apple health"), "not represented as owning the source")
        XCTAssertTrue(
            provenance.contains("does not change anything in apple health"),
            "deleting here doesn't touch Health")
        XCTAssertEqual(payload.records.count, 1)
        XCTAssertEqual(payload.exportedAt, now)
    }

    func testExportContainsOnlyCoarseDerivedAggregatesNotRawSamples() {
        // A derived record is a coarse daily aggregate — its fields are {date, asleepDuration}, never a
        // raw HealthKit sample.
        let mirror = Mirror(reflecting: record(-1, 7 * 3_600))
        XCTAssertEqual(Set(mirror.children.compactMap(\.label)), ["date", "asleepDuration"])
    }

    func testExportAfterDeleteIsEmpty() async throws {
        let sut = fixture([record(-1, 7 * 3_600)]).sut
        _ = try await sut.deleteAllDerivedData(now: now)
        let payload = try await sut.export(now: now)
        XCTAssertTrue(payload.records.isEmpty)
    }
}

private actor InMemoryDerivedWellnessStore: DerivedWellnessStore {
    private var stored: [DerivedWellnessRecord]
    init(_ records: [DerivedWellnessRecord]) { stored = records }
    func records() -> [DerivedWellnessRecord] { stored }
    func deleteAll() -> Int {
        let count = stored.count
        stored = []
        return count
    }
}

private actor RecordingDeletionAudit: WellnessDeletionAuditing {
    private(set) var recorded: [WellnessDeletionReceipt] = []
    func record(_ receipt: WellnessDeletionReceipt) { recorded.append(receipt) }
}
