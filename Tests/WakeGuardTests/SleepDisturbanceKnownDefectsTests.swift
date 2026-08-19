import Foundation
import XCTest

@testable import WakeGuard

/// WG-313: the **open** defects in the night estimate, pinned as expected failures so they stay visible in
/// CI rather than in prose. Round-ten review findings (H4/H5/H6), all reachable by ordinary data and none
/// of them H2 (block ranking) or H3 (sample extrapolation), which are pinned in
/// `SleepDisturbanceNightAnchorTests` and `SleepDisturbanceSampleValidityTests` respectively.
///
/// **One assertion per expected-failure test, deliberately.** `XCTExpectFailure` is satisfied by a *single*
/// failing assertion, so bundling a repro's assertions lets a partial fix turn the test green while the rest
/// of the defect ships. These are the acceptance gate for WG-317, so that failure mode is not academic.
final class SleepDisturbanceKnownDefectsTests: XCTestCase {

    /// The night and both estimates, resolved together.
    private struct Summary {
        let night: DateInterval?
        let disturbances: SleepDisturbances?
        let rest: TimeInterval?
    }

    /// A calendar pinned to a fixed zone, so "previous local 18:00" is deterministic in tests.
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZone = TimeZone(identifier: zone) { calendar.timeZone = timeZone }
        return calendar
    }

    /// Builds an instant from local wall-clock components in `zone`.
    private func local(
        _ zone: String, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0
    ) -> Date {
        let calendar = calendar(zone)
        let components = DateComponents(
            timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour,
            minute: minute)
        return calendar.date(from: components) ?? .distantPast
    }

    /// Resolve the night and both estimates exactly as `ReadinessViewModel` does.
    private func summary(_ samples: [MotionActivitySample], at now: Date, zone: String) -> Summary {
        let span = SleepDisturbanceEstimator.candidateSpan(endingAt: now, calendar: calendar(zone))
        guard let night = SleepDisturbanceEstimator.nightSpan(samples: samples, in: span) else {
            return Summary(night: nil, disturbances: nil, rest: nil)
        }
        return Summary(
            night: night,
            disturbances: SleepDisturbanceEstimator.estimate(samples: samples, window: night),
            rest: SleepDisturbanceEstimator.longestRestWindow(samples: samples, window: night))
    }

    /// A night broken by awakenings **longer** than `maxDisturbanceGap`: asleep 23:00, up for 25 minutes at
    /// 01:00, 03:00 and 05:00, out of bed at 07:00, screen opened at 07:45.
    private func nightWithLongAwakenings(zone: String) -> [MotionActivitySample] {
        var samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 22), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 23), quality: .high, kind: .stationary),
        ]
        for hour in [1, 3, 5] {
            samples.append(
                MotionActivitySample(
                    timestamp: local(zone, 2026, 5, 12, hour), quality: .high, kind: .walking))
            samples.append(
                MotionActivitySample(
                    timestamp: local(zone, 2026, 5, 12, hour, 25), quality: .high,
                    kind: .stationary))
        }
        samples.append(
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 7), quality: .high, kind: .walking))
        samples.append(
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 7, 30), quality: .high, kind: .stationary))
        return samples
    }

    /// **Known defect (WG-313 H4), not fixed.** `nightSpan` closes a block at `blockEnd` — the **start** of
    /// the run that terminated it (`SleepDisturbanceEstimator.swift:98-107`) — and `ReadinessViewModel` then
    /// counts disturbances with `window: night`. The terminating run is therefore *outside* the counting
    /// window by construction, so `pickups` is not "overnight disturbances" but "overnight disturbances
    /// shorter than `maxDisturbanceGap`".
    ///
    /// The bias runs the wrong way: the worse the night, the more certainly the count reads zero, and
    /// `MovementEstimateCopy.disturbanceText` renders zero as "No overnight movement detected." — a
    /// *reassuring falsehood* on the one signal this feature is named for. The estimator's documented
    /// under-counting bias ("a missed disturbance is harmless") does not cover this case.
    ///
    /// Distinct from H2 and H3: no daytime block competes (the screen is opened minutes after waking), the
    /// samples are dense with no gaps to extrapolate across, and a coverage model cannot help because every
    /// minute is observed. One assertion per expected-failure test on purpose — `XCTExpectFailure` is
    /// satisfied by a *single* failing assertion, so a bundled repro goes green on a partial fix.
    func testALongAwakeningIsCountedRatherThanDeletingItselfFromTheCount() {
        XCTExpectFailure(
            "WG-313 H4: the run that ends a block is excluded from the block's own count")
        let zone = "America/New_York"
        let resolved = summary(
            nightWithLongAwakenings(zone: zone), at: local(zone, 2026, 5, 12, 7, 45), zone: zone)
        XCTAssertEqual(
            resolved.disturbances?.pickups, 3,
            "three 25-minute awakenings are the answer the user came for; the section reports none")
    }

    /// **Known defect (WG-313 H4), not fixed.** The same mechanism truncates the night itself: the reported
    /// night is only 23:00–01:00, so an 8-hour night with three awakenings renders as "~2h of low activity
    /// overnight". The two lines are then jointly incoherent — a short, undisturbed night.
    func testALongAwakeningDoesNotTruncateTheNightToItsFirstStretch() {
        XCTExpectFailure(
            "WG-313 H4: a run over maxDisturbanceGap splits the night rather than sitting in it")
        let zone = "America/New_York"
        let resolved = summary(
            nightWithLongAwakenings(zone: zone), at: local(zone, 2026, 5, 12, 7, 45), zone: zone)
        XCTAssertEqual(
            resolved.night?.end, local(zone, 2026, 5, 12, 7),
            "the night ends when the sleeper got up, not at the first awakening")
    }

    /// **Known defect (WG-313 H5), not fixed.** `minimumNightDuration` is documented as "the shortest
    /// **quiet** block that may be called a night", but the guard at `SleepDisturbanceEstimator.swift:112`
    /// tests `longest.duration` — which includes every merged interior moving run. An evening of chores
    /// (19-minute bursts, each just under `maxDisturbanceGap`, separated by short sits) is therefore accepted
    /// as the night while being 77% movement.
    ///
    /// The section then renders "Little low-activity time overnight." beside "Movement detected 7 times
    /// overnight" — the WG-318 empty section arriving through the `.available` branch, which
    /// `testNoSuccessLineIsBlank` cannot see because the string is not blank, merely contentless.
    func testABlockThatIsMostlyMovementIsNotAcceptedAsTheNight() {
        XCTExpectFailure(
            "WG-313 H5: minimumNightDuration gates the block's length, not its quietness")
        let zone = "America/New_York"
        // Seven 19-minute bursts from 18:00, each just under `maxDisturbanceGap` so no run ever closes the
        // block, separated by 5-minute sits. The screen is opened at 21:12, five minutes after the last
        // burst ends, so the block is [18:19, 21:12] — 2h53m, of which 7 × 19m = 2h13m is movement.
        var samples: [MotionActivitySample] = []
        for burst in 0..<7 {
            let minute = burst * 24
            samples.append(
                MotionActivitySample(
                    timestamp: local(zone, 2026, 5, 12, 18, minute), quality: .high, kind: .walking)
            )
            samples.append(
                MotionActivitySample(
                    timestamp: local(zone, 2026, 5, 12, 18, minute + 19), quality: .high,
                    kind: .stationary))
        }
        let resolved = summary(samples, at: local(zone, 2026, 5, 12, 21, 12), zone: zone)
        XCTAssertNil(
            resolved.night,
            "a stretch that is 77% movement is an evening of chores, not a night; report unavailable"
        )
    }

    /// **Known defect (WG-313 H6), not fixed.** The WG-313 ADR claims the evening anchor keeps "the most
    /// recently completed night reachable **all day** instead of vanishing each evening". It does not:
    /// `candidateSpan` anchors to the previous *local day*, so at local midnight the anchor jumps forward a
    /// full day and the completed night falls out of the span.
    ///
    /// This is the headline WG-313 symptom — the section changing depending on when the screen is opened —
    /// surviving one boundary over. `testSummaryIsIdenticalWhateverTimeTheScreenIsOpened` compares 07:00
    /// against 09:00 on the same local day, so no test in this file crosses local midnight.
    func testTheCompletedNightSurvivesLocalMidnight() {
        XCTExpectFailure(
            "WG-313 H6: the evening anchor moves the cliff to midnight rather than removing it")
        let zone = "America/New_York"
        // Asleep 22:30 on the 10th until 07:00 on the 11th, out all day, settles again at 22:00.
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 10, 22, 30), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 7), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 22), quality: .high, kind: .stationary),
        ]
        let beforeMidnight = summary(samples, at: local(zone, 2026, 5, 11, 23, 55), zone: zone)
        let afterMidnight = summary(samples, at: local(zone, 2026, 5, 12, 0, 5), zone: zone)
        XCTAssertEqual(
            beforeMidnight.rest, afterMidnight.rest,
            "the same data ten minutes apart reports 8h30m and then 2h5m of low activity")
    }
}
