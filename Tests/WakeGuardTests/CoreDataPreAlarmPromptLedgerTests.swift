import XCTest

@testable import WakeGuard

/// WG-089: the persisted pre-alarm prompt ledger. Verifies the idempotency `claim` is atomic and
/// **survives across ledger instances** (an app-relaunch proxy — so a foreground fallback after a
/// background prompt de-dups), that concurrent claims of the same key yield exactly one winner, that
/// distinct keys are independent, and that expired claims are pruned.
final class CoreDataPreAlarmPromptLedgerTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 189)
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func key(alarm: AlarmID? = nil, occurrence offset: TimeInterval = 3600)
        -> PreAlarmPromptKey
    {
        PreAlarmPromptKey(
            alarmID: alarm ?? AlarmID(ids.next()), occurrence: now.addingTimeInterval(offset))
    }

    func testClaimIsIdempotent() async throws {
        let ledger = CoreDataPreAlarmPromptLedger(try PersistenceController(inMemory: true))
        let promptKey = key()

        let first = await ledger.claim(promptKey, at: now)
        let second = await ledger.claim(promptKey, at: now)

        XCTAssertTrue(first)
        XCTAssertFalse(second, "the same (alarm, occurrence) is claimed at most once")
    }

    func testClaimPersistsAcrossLedgerInstances() async throws {
        let controller = try PersistenceController(inMemory: true)
        let promptKey = key()

        let first = await CoreDataPreAlarmPromptLedger(controller).claim(promptKey, at: now)
        // A fresh ledger over the SAME store — an app-relaunch proxy — sees the persisted claim.
        let second = await CoreDataPreAlarmPromptLedger(controller).claim(promptKey, at: now)

        XCTAssertTrue(first)
        XCTAssertFalse(second, "the claim is persisted — a new instance (relaunch) de-dups")
    }

    func testDistinctKeysBothClaim() async throws {
        let ledger = CoreDataPreAlarmPromptLedger(try PersistenceController(inMemory: true))
        let alarm = AlarmID(ids.next())

        let tonight = await ledger.claim(key(alarm: alarm, occurrence: 3600), at: now)
        let tomorrow = await ledger.claim(key(alarm: alarm, occurrence: 90000), at: now)

        XCTAssertTrue(tonight)
        XCTAssertTrue(tomorrow)
    }

    func testConcurrentClaimsOfSameKeyYieldExactlyOneWinner() async throws {
        let controller = try PersistenceController(inMemory: true)
        let promptKey = key()
        let now = self.now
        // Two independent ledger actors over the same store race the same key — the uniqueness
        // constraint (+ fail-closed on the losing insert) must make exactly one win.
        let ledgerA = CoreDataPreAlarmPromptLedger(controller)
        let ledgerB = CoreDataPreAlarmPromptLedger(controller)

        async let resultA = ledgerA.claim(promptKey, at: now)
        async let resultB = ledgerB.claim(promptKey, at: now)
        let winners = await [resultA, resultB].filter { $0 }

        XCTAssertEqual(winners.count, 1, "exactly one concurrent claim surfaces the prompt")
    }

    func testExpiredClaimsArePrunedAndCanBeReclaimed() async throws {
        let ledger = CoreDataPreAlarmPromptLedger(try PersistenceController(inMemory: true))
        let promptKey = key()
        _ = await ledger.claim(promptKey, at: now)

        // A claim 49 h later prunes the original (surfacedAt now < later − 48 h retention).
        let later = now.addingTimeInterval(49 * 3600)
        _ = await ledger.claim(key(occurrence: 90000), at: later)

        let reclaimed = await ledger.claim(promptKey, at: later)
        XCTAssertTrue(reclaimed, "an expired claim is pruned and can be re-claimed")
    }
}
