import Foundation
import XCTest

@testable import WakeGuard

/// WG-073: the challenge runtime drives the real pipeline — live pedometer → `ChallengeObservationReducer`
/// → `WakeChallengeMachine` → `ChallengeStopCoordinator` → `AlarmCommandProcessing`. Proves a corroborated
/// walk passes and submits **exactly one** authorized stop (#24), a shake never passes and submits nothing
/// (#20), and an unavailable sensor offers the accessible fallback without a stop (#21/#22) — the fallback
/// then submits exactly one.
@MainActor
final class WakeChallengeRuntimeTests: XCTestCase {

    private let alarmID = AlarmID(DeterministicIDGenerator(seed: 1).next())
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func samples(_ counts: [Int]) -> [PedometerSample] {
        counts.enumerated().map { index, steps in
            PedometerSample(
                timestamp: base.addingTimeInterval(Double(index)), quality: .high, stepCount: steps)
        }
    }

    private func makeRuntime(
        pedometer: any PedometerSource, processor: FakeAlarmCommandProcessor, required: Int = 20
    ) -> WakeChallengeRuntime {
        WakeChallengeRuntime(
            alarmID: alarmID, required: required, pedometer: pedometer, processor: processor)
    }

    func testCorroboratedWalkPassesAndSubmitsExactlyOneStop() async {
        let processor = FakeAlarmCommandProcessor()
        let pedometer = FakePedometerSource(
            availabilityState: .available,
            cannedSamples: samples([0, 2, 4, 7, 9, 11, 14, 16, 18, 20]))
        let runtime = makeRuntime(pedometer: pedometer, processor: processor)

        await runtime.drive()
        await runtime.passSubmission?.value  // the stop is submitted off-task (WG-295 D7)

        XCTAssertEqual(runtime.viewModel.machine.phase, .passed, "a corroborated walk passes (#19)")
        XCTAssertEqual(
            processor.seen, [.markChallengePassed(alarmID)],
            "a valid pass submits exactly one authorized stop (#24)")
    }

    func testShakeNeverPassesAndSubmitsNoStop() async {
        let processor = FakeAlarmCommandProcessor()
        let pedometer = FakePedometerSource(
            availabilityState: .available,
            cannedSamples: samples([0, 5, 6, 12, 13, 20, 21, 28, 29, 35]))
        let runtime = makeRuntime(pedometer: pedometer, processor: processor)

        await runtime.drive()

        XCTAssertNotEqual(runtime.viewModel.machine.phase, .passed, "a shake must never pass (#20)")
        XCTAssertTrue(processor.seen.isEmpty, "a shake submits no stop")
    }

    func testUnavailableSensorOffersFallbackAndOnlyItStops() async {
        let processor = FakeAlarmCommandProcessor()
        let pedometer = FakePedometerSource(availabilityState: .notAuthorized)
        let runtime = makeRuntime(pedometer: pedometer, processor: processor)

        await runtime.drive()
        XCTAssertEqual(
            runtime.viewModel.machine.phase, .unavailable,
            "an unavailable sensor is non-trapping (#21)")
        XCTAssertTrue(
            runtime.viewModel.offersAccessibleAlternative, "the fallback is offered (#22)")
        XCTAssertTrue(processor.seen.isEmpty, "sensor unavailability alone never stops the alarm")

        await runtime.accessibleAlternativePassed()
        XCTAssertEqual(
            processor.seen, [.markChallengePassed(alarmID)],
            "the accessible alternative submits exactly one stop")
    }

    func testNotYetAskedRequestsMotionThenProceedsToPass() async {
        let processor = FakeAlarmCommandProcessor()
        let pedometer = GrantOnRequestPedometer(
            granted: samples([0, 2, 4, 7, 9, 11, 14, 16, 18, 20]))
        let runtime = makeRuntime(pedometer: pedometer, processor: processor)

        await runtime.drive()
        await runtime.passSubmission?.value  // the stop is submitted off-task (WG-295 D7)

        XCTAssertEqual(
            runtime.viewModel.machine.phase, .passed,
            "not-yet-asked triggers the Motion prompt in context, then the walk proceeds (WG-061)")
        XCTAssertEqual(
            processor.seen, [.markChallengePassed(alarmID)],
            "after granting, a valid pass submits exactly one stop")
    }
}

/// A pedometer that reports Motion & Fitness as **not-yet-asked**, then **grants** on the in-context request
/// — modelling the real device flow (WG-061): the challenge triggers the prompt and proceeds after allow.
private struct GrantOnRequestPedometer: PedometerSource {
    let granted: [PedometerSample]
    func availability() async -> MotionSourceAvailability { .notAuthorized }
    func requestAuthorization() async -> MotionSourceAvailability { .available }
    func samples() -> AsyncThrowingStream<PedometerSample, Error> {
        FakeMotionStream.make(granted, availability: .available, failAfter: nil)
    }
}
