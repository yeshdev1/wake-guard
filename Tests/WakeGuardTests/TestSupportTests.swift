import Foundation
import XCTest

/// WG-007: proves the deterministic test-support primitives behave predictably.
/// (`TestClock`, `DeterministicIDGenerator`, `InMemoryRepository` are compiled
/// into this test target from `Tests/TestSupport/`.)
final class TestSupportTests: XCTestCase {

    func testTestClockOnlyMovesWhenMoved() {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(clock.now, Date(timeIntervalSince1970: 1_000))

        clock.advance(by: 60)
        XCTAssertEqual(clock.now, Date(timeIntervalSince1970: 1_060))

        clock.set(Date(timeIntervalSince1970: 0))
        XCTAssertEqual(clock.now, Date(timeIntervalSince1970: 0))
    }

    func testDeterministicIDGeneratorIsReproducibleAndUnique() {
        let genA = DeterministicIDGenerator(seed: 0)
        let genB = DeterministicIDGenerator(seed: 0)

        let seqA = (0..<5).map { _ in genA.next() }
        let seqB = (0..<5).map { _ in genB.next() }

        XCTAssertEqual(seqA, seqB, "same seed -> identical sequence")
        XCTAssertEqual(Set(seqA).count, 5, "identifiers are unique")
        XCTAssertEqual(genA.next(), genB.next(), "generators stay in lockstep")
    }

    func testDeterministicIDGeneratorSeedsDiffer() {
        let genA = DeterministicIDGenerator(seed: 0)
        let genB = DeterministicIDGenerator(seed: 100)
        XCTAssertNotEqual(genA.next(), genB.next())
    }

    func testInMemoryRepositoryUpsertFetchDeleteInOrder() {
        struct Item: Identifiable, Sendable, Equatable {
            let id: Int
            var name: String
        }

        let repo = InMemoryRepository<Item>()
        repo.upsert(Item(id: 1, name: "a"))
        repo.upsert(Item(id: 2, name: "b"))
        repo.upsert(Item(id: 1, name: "a2"))  // update in place, not a new row

        XCTAssertEqual(repo.count, 2)
        XCTAssertEqual(repo.fetch(id: 1)?.name, "a2")
        XCTAssertEqual(repo.all().map(\.id), [1, 2], "insertion order preserved")

        repo.delete(id: 1)
        XCTAssertNil(repo.fetch(id: 1))
        XCTAssertEqual(repo.all().map(\.id), [2])
    }

    func testInMemoryRepositoryReinsertAppendsAndInvariantsHold() {
        struct Item: Identifiable, Sendable {
            let id: Int
        }
        let repo = InMemoryRepository<Item>([Item(id: 1), Item(id: 2), Item(id: 3)])
        XCTAssertNil(repo.fetch(id: 99), "missing id returns nil")

        repo.delete(id: 1)
        repo.upsert(Item(id: 1))
        XCTAssertEqual(repo.all().map(\.id), [2, 3, 1], "delete then reinsert appends")
        XCTAssertEqual(repo.count, repo.all().count, "count stays consistent with all()")
    }

    func testDeterministicIDGeneratorIsThreadSafe() async {
        let generator = DeterministicIDGenerator(seed: 0)
        let total = 1_000
        let ids = await withTaskGroup(of: UUID.self) { group in
            for _ in 0..<total {
                group.addTask { generator.next() }
            }
            var collected: [UUID] = []
            for await id in group {
                collected.append(id)
            }
            return collected
        }
        XCTAssertEqual(ids.count, total)
        XCTAssertEqual(Set(ids).count, total, "no lost updates or duplicate ids under concurrency")
    }

    func testInMemoryRepositoryIsThreadSafe() async {
        struct Item: Identifiable, Sendable {
            let id: Int
        }
        let repo = InMemoryRepository<Item>()
        let total = 500
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<total {
                group.addTask { repo.upsert(Item(id: index)) }
            }
            for await _ in group {}
        }
        XCTAssertEqual(repo.count, total)
        XCTAssertEqual(
            Set(repo.all().map(\.id)).count, total,
            "every concurrent upsert landed exactly once")
    }
}
