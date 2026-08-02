import CoreData
import XCTest

@testable import WakeGuard

/// WG-016: the Core Data external-operation outbox. Covers the full lifecycle
/// (pending/inProgress/applied/uncertain/failed), idempotent enqueue on the
/// idempotency key (incl. under a concurrent race), launch-recovery of non-terminal
/// entries, the bounded retry budget (no unbounded retries), and that a terminal
/// entry is never resurrected into a second external apply.
final class CoreDataOutboxRepositoryTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 16)

    private func makeController() throws -> PersistenceController {
        try PersistenceController(inMemory: true)
    }

    private func makeRepository(_ controller: PersistenceController) -> CoreDataOutboxRepository {
        CoreDataOutboxRepository(controller)
    }

    private func makeEntry(
        id: OutboxEntryID? = nil,
        key: String = "key-0",
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> OutboxEntry {
        OutboxEntry(
            id: id ?? OutboxEntryID(ids.next()),
            command: .disable(AlarmID(ids.next())),
            idempotencyKey: key,
            status: .pending,
            createdAt: createdAt,
            attempts: 0,
            lastFailureReason: nil)
    }

    private func assertThrows(
        _ expected: OutboxRepositoryError, _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected) to be thrown")
        } catch let error as OutboxRepositoryError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// Inserts a `.pending` `OutboxRecord` with an arbitrary (possibly corrupt)
    /// payload, bypassing the repository — simulates a future-schema or bit-rotted
    /// row that recovery must tolerate.
    private func insertRawOutbox(
        _ controller: PersistenceController, id: OutboxEntryID,
        idempotencyKey: String, payload: Data
    ) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            guard
                let entity = NSEntityDescription.entity(
                    forEntityName: "OutboxRecord", in: context)
            else {
                return XCTFail("OutboxRecord entity missing")
            }
            let record = NSManagedObject(entity: entity, insertInto: context)
            record.setValue(id.rawValue.uuidString, forKey: "id")
            record.setValue(idempotencyKey, forKey: "idempotencyKey")
            record.setValue(OutboxStatus.pending.rawValue, forKey: "status")
            record.setValue(Date(timeIntervalSince1970: 5), forKey: "createdAt")
            record.setValue(payload, forKey: "payload")
            try context.save()
        }
    }

    func testEnqueueAndLookup() async throws {
        let repo = makeRepository(try makeController())
        let empty = try await repo.pendingEntries()
        XCTAssertTrue(empty.isEmpty)

        let entry = makeEntry(key: "k1")
        try await repo.enqueue(entry)
        let byId = try await repo.entry(id: entry.id)
        XCTAssertEqual(byId, entry)
        let byKey = try await repo.entry(idempotencyKey: "k1")
        XCTAssertEqual(byKey, entry)
        let pending = try await repo.pendingEntries()
        XCTAssertEqual(pending, [entry])
    }

    func testEnqueueIsIdempotentOnKey() async throws {
        let repo = makeRepository(try makeController())
        let first = makeEntry(key: "dup")
        let second = makeEntry(key: "dup")  // distinct id, same idempotency key
        try await repo.enqueue(first)
        try await repo.enqueue(second)

        let pending = try await repo.pendingEntries()
        XCTAssertEqual(pending.count, 1, "a duplicate key must not enqueue twice")
        XCTAssertEqual(pending.first?.id, first.id, "the first enqueue wins")
        let byKey = try await repo.entry(idempotencyKey: "dup")
        XCTAssertEqual(byKey?.id, first.id)
    }

    func testLifecyclePendingToApplied() async throws {
        let repo = makeRepository(try makeController())
        let entry = makeEntry()
        try await repo.enqueue(entry)

        let pendingBefore = try await repo.pendingEntries()
        XCTAssertEqual(pendingBefore.map(\.id), [entry.id])

        try await repo.markInProgress(entry.id)
        let inProgress = try await repo.entry(id: entry.id)
        XCTAssertEqual(inProgress?.status, .inProgress)
        XCTAssertEqual(inProgress?.attempts, 1)
        let pendingDuring = try await repo.pendingEntries()
        XCTAssertTrue(pendingDuring.isEmpty, "inProgress is no longer freshly-pending")
        let unresolvedDuring = try await repo.unresolvedEntries()
        XCTAssertEqual(unresolvedDuring.map(\.id), [entry.id], "but still unresolved")

        try await repo.markApplied(entry.id)
        let applied = try await repo.entry(id: entry.id)
        XCTAssertEqual(applied?.status, .applied)
        let unresolvedAfter = try await repo.unresolvedEntries()
        XCTAssertTrue(unresolvedAfter.isEmpty, "a terminal entry needs no recovery")
    }

    func testUncertainIsRecoveredByUnresolved() async throws {
        let repo = makeRepository(try makeController())
        let entry = makeEntry()
        try await repo.enqueue(entry)
        try await repo.markInProgress(entry.id)
        try await repo.markUncertain(entry.id)

        // Recovery: an attempted-but-unknown-outcome op is surfaced for reconciliation
        // (#10 — never assume a cancellation means the op did not occur).
        let unresolved = try await repo.unresolvedEntries()
        XCTAssertEqual(unresolved.map(\.id), [entry.id])
        let stillPending = try await repo.pendingEntries()
        XCTAssertTrue(stillPending.isEmpty, "uncertain is unresolved but not pending")

        try await repo.markApplied(entry.id)
        let afterReconcile = try await repo.unresolvedEntries()
        XCTAssertTrue(afterReconcile.isEmpty)
    }

    func testMarkAppliedIsIdempotent() async throws {
        let repo = makeRepository(try makeController())
        let entry = makeEntry()
        try await repo.enqueue(entry)
        try await repo.markApplied(entry.id)
        try await repo.markApplied(entry.id)  // second call must be a no-op, not a throw
        let applied = try await repo.entry(id: entry.id)
        XCTAssertEqual(applied?.status, .applied)
    }

    func testTerminalEntryIsNotResurrected() async throws {
        let repo = makeRepository(try makeController())
        // An applied op must not be re-attempted — that would re-apply it externally.
        let done = makeEntry(key: "done")
        try await repo.enqueue(done)
        try await repo.markApplied(done.id)
        await assertThrows(.alreadyResolved(done.id)) {
            try await repo.markInProgress(done.id)
        }
        // A failed op must not be flipped to applied.
        let dead = makeEntry(key: "dead")
        try await repo.enqueue(dead)
        try await repo.markFailed(dead.id, reason: "gave up")
        await assertThrows(.alreadyResolved(dead.id)) {
            try await repo.markApplied(dead.id)
        }
    }

    func testRetryBudgetIsBounded() async throws {
        let repo = makeRepository(try makeController())
        let entry = makeEntry()
        try await repo.enqueue(entry)

        // Exhaust the budget: each attempt bumps `attempts`, capped at maxAttempts.
        for _ in 0..<CoreDataOutboxRepository.maxAttempts {
            try await repo.markInProgress(entry.id)
        }
        let attempted = try await repo.entry(id: entry.id)
        XCTAssertEqual(attempted?.attempts, CoreDataOutboxRepository.maxAttempts)

        // The next attempt is refused and the entry is failed — no unbounded retries.
        await assertThrows(.retryLimitExceeded(entry.id)) {
            try await repo.markInProgress(entry.id)
        }
        let failed = try await repo.entry(id: entry.id)
        XCTAssertEqual(failed?.status, .failed)
        XCTAssertEqual(failed?.lastFailureReason, "retry limit exceeded")
        let unresolved = try await repo.unresolvedEntries()
        XCTAssertTrue(unresolved.isEmpty, "an exhausted entry is terminal, not stranded")
    }

    func testMarkOnUnknownIdThrowsNotFound() async throws {
        let repo = makeRepository(try makeController())
        let unknown = OutboxEntryID(ids.next())
        await assertThrows(.notFound(unknown)) {
            try await repo.markApplied(unknown)
        }
    }

    func testConcurrentEnqueueOfSameKeyYieldsSingleEntry() async throws {
        let repo = makeRepository(try makeController())
        // Distinct ids, one shared idempotency key. Build before racing so only the
        // enqueues are concurrent.
        let entries = (0..<8).map { _ in makeEntry(key: "same") }

        let anyThrew = await withTaskGroup(of: Bool.self) { group in
            for entry in entries {
                group.addTask {
                    do {
                        try await repo.enqueue(entry)
                        return false
                    } catch {
                        return true
                    }
                }
            }
            var threw = false
            for await didThrow in group where didThrow { threw = true }
            return threw
        }

        XCTAssertFalse(anyThrew, "a concurrent duplicate enqueue is absorbed, not thrown")
        let pending = try await repo.pendingEntries()
        XCTAssertEqual(pending.count, 1, "the operation is queued exactly once")
    }

    private enum MarkOutcome: Sendable { case won, conflicted, leaked }

    func testConcurrentMarkInProgressNeitherLosesNorDoubleCountsAttempts() async throws {
        let repo = makeRepository(try makeController())
        let entry = makeEntry()
        try await repo.enqueue(entry)

        // Fewer than maxAttempts racing first-attempts on ONE entry (so the retry cap
        // is not involved and every failure must be a typed optimistic-lock conflict).
        // The store's `NSMergePolicy.error` must let each winning save be reflected
        // exactly once and reject stale concurrent writes — never silently merge them.
        let outcomes = await withTaskGroup(of: MarkOutcome.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    do {
                        try await repo.markInProgress(entry.id)
                        return .won
                    } catch let error as OutboxRepositoryError {
                        if case .conflict = error { return .conflicted }
                        return .leaked
                    } catch {
                        return .leaked
                    }
                }
            }
            var results: [MarkOutcome] = []
            for await outcome in group { results.append(outcome) }
            return results
        }

        let wins = outcomes.filter { $0 == .won }.count
        XCTAssertGreaterThanOrEqual(wins, 1, "at least one attempt applies")
        XCTAssertEqual(
            outcomes.filter { $0 == .leaked }.count, 0,
            "every loser is a typed .conflict, not a raw error")
        // No lost update and no double-count: attempts equals the number of winners.
        // A last-writer-wins merge policy would collapse concurrent writes and fail
        // this (attempts < wins).
        let after = try await repo.entry(id: entry.id)
        XCTAssertEqual(after?.attempts, wins, "attempts reflects exactly the winners")
        XCTAssertEqual(after?.status, .inProgress)
    }

    func testUndecodableEntryIsSkippedInRecovery() async throws {
        let controller = try makeController()
        let repo = makeRepository(controller)
        try await repo.enqueue(makeEntry(key: "good"))

        // A garbled payload (not valid OutboxEntry JSON) lands in the store.
        try await insertRawOutbox(
            controller, id: OutboxEntryID(ids.next()), idempotencyKey: "corrupt",
            payload: Data("not-json".utf8))

        // One poison row must not blind recovery: the good entry still returns.
        let unresolved = try await repo.unresolvedEntries()
        XCTAssertEqual(unresolved.map(\.idempotencyKey), ["good"])
    }
}
