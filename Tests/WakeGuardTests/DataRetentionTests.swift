import Foundation
import XCTest

@testable import WakeGuard

/// WG-182: local data retention controls. Verifies retention applies to **derived motion, audit,
/// recommendations, and journal separately**, that the **critical-audit minimum** floor is enforced (a
/// critical audit event is never purged early), and that **cleanup** selects exactly the expired records.
final class DataRetentionTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func record(
        _ category: RetentionCategory, ageDays: Double, criticalAudit: Bool = false
    ) -> RetentionRecord {
        RetentionRecord(
            category: category, createdAt: now.addingTimeInterval(-ageDays * day),
            isCriticalAudit: criticalAudit)
    }

    private func expired(_ records: [RetentionRecord], policy: RetentionPolicy = .default) -> Set<
        RetentionRecord
    > {
        Set(RetentionCleanup.expired(records, policy: policy, now: now))
    }

    // MARK: each category expires on its own window

    func testEachCategoryHasItsOwnWindow() {
        // default windows: motion 14d, recommendations 30d, audit 180d, journal 365d.
        XCTAssertTrue(expired([record(.derivedMotion, ageDays: 15)]).count == 1)
        XCTAssertTrue(expired([record(.derivedMotion, ageDays: 13)]).isEmpty)

        XCTAssertTrue(expired([record(.recommendations, ageDays: 31)]).count == 1)
        XCTAssertTrue(expired([record(.recommendations, ageDays: 29)]).isEmpty)

        XCTAssertTrue(expired([record(.audit, ageDays: 181)]).count == 1)
        XCTAssertTrue(expired([record(.audit, ageDays: 179)]).isEmpty)

        XCTAssertTrue(expired([record(.journal, ageDays: 366)]).count == 1)
        XCTAssertTrue(expired([record(.journal, ageDays: 364)]).isEmpty)
    }

    // MARK: critical-audit minimum floor (365 days)

    func testCriticalAuditIsKeptToTheDocumentedFloor() {
        // 200 days is past the 180-day audit window but before the 365-day critical floor → retained.
        XCTAssertTrue(expired([record(.audit, ageDays: 200, criticalAudit: true)]).isEmpty)
        // Past the floor → expired.
        XCTAssertEqual(expired([record(.audit, ageDays: 366, criticalAudit: true)]).count, 1)
    }

    func testCriticalFloorOverridesAShorterAuditWindow() {
        let shortAudit = RetentionPolicy(
            derivedMotion: 14 * day, audit: 30 * day, recommendations: 30 * day, journal: 365 * day)
        // Even with a 30-day audit window, a critical audit event at 100 days is retained by the floor.
        XCTAssertTrue(
            expired([record(.audit, ageDays: 100, criticalAudit: true)], policy: shortAudit).isEmpty
        )
        // A non-critical audit event at 100 days is expired under the same short window.
        XCTAssertEqual(
            expired([record(.audit, ageDays: 100)], policy: shortAudit).count, 1)
    }

    func testCriticalAuditMinimumIsThreeSixtyFiveDays() {
        XCTAssertEqual(RetentionPolicy.criticalAuditMinimum, 365 * day)
    }

    // MARK: categories are cleaned independently, cleanup selects the right set

    func testSeparateCategoriesAreCleanedIndependently() {
        let records = [
            record(.derivedMotion, ageDays: 20),  // expired (>14)
            record(.derivedMotion, ageDays: 5),  // kept
            record(.recommendations, ageDays: 40),  // expired (>30)
            record(.audit, ageDays: 100),  // kept (<180)
            record(.audit, ageDays: 400, criticalAudit: true),  // expired (>365 floor)
            record(.journal, ageDays: 10),  // kept
        ]
        let gone = expired(records)
        XCTAssertEqual(gone.count, 3)
        XCTAssertEqual(
            RetentionCleanup.retained(records, now: now).count, records.count - gone.count)
    }

    func testEmptyInputYieldsNothing() {
        XCTAssertTrue(RetentionCleanup.expired([], now: now).isEmpty)
    }
}
