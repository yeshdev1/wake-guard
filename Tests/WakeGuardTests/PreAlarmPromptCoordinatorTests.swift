import XCTest

@testable import WakeGuard

/// WG-089: the pre-alarm prompt coordinator (foreground fallback de-dup). Verifies a prompt surfaces
/// **at most once per (alarm, occurrence)** via the ledger's idempotency claim — so an app launch
/// after a background prompt doesn't duplicate it — that a declined recommendation doesn't consume the
/// key, and that distinct occurrences surface independently. The coordinator holds no alarm authority.
final class PreAlarmPromptCoordinatorTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 89)
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func prompting() throws -> PreAlarmRecommendation {
        let policy = try PreAlarmPolicy.enabled(leadTime: 600)
        let evidence = AwakeEvidenceModel.evaluate(
            AwakeEvidenceInput(
                recentStepCount: 30, longestEpisodeDuration: 0, secondsSinceLastMovement: 60,
                deviceInteracted: false))
        return PreAlarmEvaluator.evaluate(
            policy: policy, criticality: .standard, timeRemaining: 300, evidence: evidence)
    }

    private func declining() -> PreAlarmRecommendation {
        let evidence = AwakeEvidenceModel.evaluate(
            AwakeEvidenceInput(
                recentStepCount: 0, longestEpisodeDuration: 0, secondsSinceLastMovement: .infinity,
                deviceInteracted: false))
        return PreAlarmEvaluator.evaluate(
            policy: .disabled, criticality: .standard, timeRemaining: 300, evidence: evidence)
    }

    private func key(alarm: AlarmID, occurrence offset: TimeInterval) -> PreAlarmPromptKey {
        PreAlarmPromptKey(alarmID: alarm, occurrence: now.addingTimeInterval(offset))
    }

    func testSurfacesOnceThenSuppressesDuplicate() async throws {
        let coordinator = PreAlarmPromptCoordinator(ledger: InMemoryPreAlarmPromptLedger())
        let recommendation = try prompting()
        let promptKey = key(alarm: AlarmID(ids.next()), occurrence: 3600)

        let first = await coordinator.surface(recommendation, for: promptKey, at: now)
        let second = await coordinator.surface(recommendation, for: promptKey, at: now)

        XCTAssertTrue(first, "the first evaluation surfaces the prompt")
        XCTAssertFalse(
            second, "a second evaluation of the same occurrence suppresses the duplicate")
    }

    func testDeclinedRecommendationDoesNotConsumeTheKey() async throws {
        let coordinator = PreAlarmPromptCoordinator(ledger: InMemoryPreAlarmPromptLedger())
        let promptKey = key(alarm: AlarmID(ids.next()), occurrence: 3600)

        let declined = await coordinator.surface(declining(), for: promptKey, at: now)
        let laterPrompt = await coordinator.surface(try prompting(), for: promptKey, at: now)

        XCTAssertFalse(declined, "a declined recommendation surfaces nothing")
        XCTAssertTrue(
            laterPrompt,
            "declining didn't claim the key — a later prompting evaluation still surfaces")
    }

    func testKeyIdentifierDoesNotTrapOnExtremeOccurrences() {
        // `.distantFuture` is finite but ~6.4e19 (> Int64.max); the identifier must not trap.
        let alarm = AlarmID(ids.next())
        XCTAssertFalse(
            PreAlarmPromptKey(alarmID: alarm, occurrence: .distantFuture).identifier.isEmpty)
        XCTAssertFalse(
            PreAlarmPromptKey(alarmID: alarm, occurrence: .distantPast).identifier.isEmpty)
        XCTAssertFalse(
            PreAlarmPromptKey(alarmID: alarm, occurrence: Date(timeIntervalSince1970: .nan))
                .identifier.isEmpty)
    }

    func testKeyIdentifierIsWholeSecondStable() {
        let alarm = AlarmID(ids.next())
        let base = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(
            PreAlarmPromptKey(alarmID: alarm, occurrence: base.addingTimeInterval(0.4)).identifier,
            PreAlarmPromptKey(alarmID: alarm, occurrence: base.addingTimeInterval(0.9)).identifier,
            "two instants in the same second share a key")
        XCTAssertNotEqual(
            PreAlarmPromptKey(alarmID: alarm, occurrence: base).identifier,
            PreAlarmPromptKey(alarmID: alarm, occurrence: base.addingTimeInterval(1)).identifier,
            "a later second is a different key")
    }

    func testCrossAlarmSameOccurrenceDoNotCollide() async throws {
        // Two different alarms firing at the same instant must not suppress each other.
        let coordinator = PreAlarmPromptCoordinator(ledger: InMemoryPreAlarmPromptLedger())
        let recommendation = try prompting()

        let alarmA = await coordinator.surface(
            recommendation, for: key(alarm: AlarmID(ids.next()), occurrence: 3600), at: now)
        let alarmB = await coordinator.surface(
            recommendation, for: key(alarm: AlarmID(ids.next()), occurrence: 3600), at: now)

        XCTAssertTrue(alarmA)
        XCTAssertTrue(alarmB, "different alarms are different keys — no cross-alarm suppression")
    }

    func testDistinctOccurrencesSurfaceIndependently() async throws {
        let coordinator = PreAlarmPromptCoordinator(ledger: InMemoryPreAlarmPromptLedger())
        let recommendation = try prompting()
        let alarm = AlarmID(ids.next())

        let tonight = await coordinator.surface(
            recommendation, for: key(alarm: alarm, occurrence: 3600), at: now)
        let tomorrow = await coordinator.surface(
            recommendation, for: key(alarm: alarm, occurrence: 90000), at: now)

        XCTAssertTrue(tonight)
        XCTAssertTrue(
            tomorrow, "a different occurrence is a different key — surfaces independently")
    }
}
