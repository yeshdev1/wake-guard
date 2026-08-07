import XCTest

@testable import WakeGuard

/// WG-048: the read-only alarm history / audit view model. Verifies each audit event maps to a
/// human-readable "who / what / when / outcome" row, that recovery actions are distinguishable
/// (#50), that the state-hash and correlation-id fingerprints never reach the presented strings
/// (#41), and that empty / failed / newest-first states are correct.
@MainActor
final class AlarmHistoryViewModelTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 48)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        actor: AuditActor = .user, source: CommandSource = .userInterface,
        outcome: Outcome = .succeeded, reason: String = "Alarm saved.", at seconds: TimeInterval,
        for alarmID: AlarmID, oldHash: String? = "old", newHash: String? = "new",
        correlation: UUID? = nil
    ) -> AuditEvent {
        AuditEvent(
            id: AuditEventID(ids.next()), actor: actor, command: .disable(alarmID),
            oldStateHash: oldHash, newStateHash: newHash,
            timestamp: Date(timeIntervalSince1970: seconds), source: source, outcome: outcome,
            correlationID: CorrelationID(correlation ?? ids.next()), userVisibleReason: reason)
    }

    private func makeVM(_ repo: StubAuditRepository, alarmID: AlarmID) -> AlarmHistoryViewModel {
        AlarmHistoryViewModel(audit: repo, clock: TestClock(now: now), alarmID: alarmID)
    }

    func testEmptyWhenNoEvents() async {
        let vm = makeVM(StubAuditRepository(), alarmID: AlarmID(ids.next()))
        await vm.load()
        XCTAssertEqual(vm.state, .empty)
    }

    func testFailedWhenStorageThrows() async {
        let vm = makeVM(StubAuditRepository(shouldThrow: true), alarmID: AlarmID(ids.next()))
        await vm.load()
        guard case .failed = vm.state else {
            return XCTFail("a storage error must surface as a failed state, not empty")
        }
    }

    func testLoadedNewestFirst() async {
        let id = AlarmID(ids.next())
        let older = event(reason: "Alarm saved.", at: 100, for: id)
        let newer = event(reason: "Alarm disabled.", at: 200, for: id)
        let vm = makeVM(StubAuditRepository(stored: [older, newer]), alarmID: id)
        await vm.load()
        guard case .loaded(let items) = vm.state else { return XCTFail("expected loaded") }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.what, "Alarm disabled.", "newest first")
        XCTAssertEqual(items.last?.what, "Alarm saved.")
    }

    func testWhoWhatOutcomeAreHumanReadable() async {
        let id = AlarmID(ids.next())
        let alarmEvent = event(
            actor: .user, outcome: .succeeded, reason: "Alarm saved.", at: 100, for: id)
        let vm = makeVM(StubAuditRepository(stored: [alarmEvent]), alarmID: id)
        await vm.load()
        guard case .loaded(let items) = vm.state, let item = items.first else {
            return XCTFail("expected an item")
        }
        XCTAssertEqual(item.who, "You")
        XCTAssertEqual(item.what, "Alarm saved.")
        XCTAssertEqual(item.outcome, .succeeded)
        XCTAssertFalse(item.isSystem, "a user edit is not a system action")
        XCTAssertFalse(item.when.isEmpty, "a relative time is shown")
    }

    func testRecoveryAndReconciliationAreDistinct() {
        let id = AlarmID(ids.next())
        // Both a recovery and a reconciliation must be distinguishable from ordinary edits (#50).
        let recovery = event(
            actor: .recovery, source: .recovery, reason: "Alarm re-armed.", at: 100, for: id)
        let recoveryItem = AlarmHistoryViewModel.item(from: recovery, now: now)
        XCTAssertTrue(recoveryItem.isSystem, "#50: recovery is distinguishable")
        XCTAssertTrue(
            recoveryItem.accessibilityLabel.localizedCaseInsensitiveContains("system action"))

        let reconcile = event(
            actor: .systemReconciliation, source: .reconciliation,
            reason: "Re-synced this alarm to your saved settings.", at: 100, for: id)
        let reconcileItem = AlarmHistoryViewModel.item(from: reconcile, now: now)
        XCTAssertTrue(reconcileItem.isSystem, "#50: reconciliation is distinguishable, not an edit")
    }

    func testSensitiveInternalsAreNotExposed() {
        let id = AlarmID(ids.next())
        let secretHash = "DEADBEEFCAFE0001"
        let secretCorrelation = UUID()
        let sensitive = event(
            reason: "Alarm saved.", at: 100, for: id, oldHash: secretHash, newHash: secretHash,
            correlation: secretCorrelation)
        let item = AlarmHistoryViewModel.item(from: sensitive, now: now)
        // #41: the state-hash and correlation-id fingerprints never reach the presented strings.
        let surfaced = [
            item.who, item.what, item.when, item.whenDetailed, item.fromSource,
            item.accessibilityLabel,
        ].joined(separator: " ")
        XCTAssertFalse(surfaced.localizedCaseInsensitiveContains(secretHash), "no state hash")
        XCTAssertFalse(
            surfaced.localizedCaseInsensitiveContains(secretCorrelation.uuidString),
            "no correlation id")
    }
}

/// A configurable in-memory `AuditRepository` for the history tests.
private struct StubAuditRepository: AuditRepository {
    var stored: [AuditEvent] = []
    var shouldThrow = false

    func append(_ event: AuditEvent) async throws {}

    func events(forAlarm id: AlarmID) async throws -> [AuditEvent] {
        if shouldThrow { throw AlarmRepositoryError.storageUnavailable }
        return stored.filter { $0.alarmID == id }
    }

    func allEvents() async throws -> [AuditEvent] { stored }
}
