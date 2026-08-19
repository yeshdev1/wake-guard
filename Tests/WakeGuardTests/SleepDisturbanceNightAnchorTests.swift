import Foundation
import XCTest

@testable import WakeGuard

/// WG-313: the night is anchored to the **data**, not the clock. Verifies the candidate span is a local
/// evening anchor, that the night is the longest quiet block once brief disturbances are merged in, and
/// that the same samples read at different times of the morning report the **same** night — the drift the
/// rolling `[now - 10h, now]` window caused. Also covers the H2 ranking cases (a sedentary day must not
/// outrank the night), DST, and time-zone-change nights. How far a sample may be extrapolated is pinned
/// separately in `SleepDisturbanceSampleValidityTests` (H3).
final class SleepDisturbanceNightAnchorTests: XCTestCase {

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

    /// Builds an instant from local wall-clock components in `zone`. The identifiers and components here
    /// are all valid, so the fallback is unreachable — and any slip would fail the assertions loudly.
    private func local(
        _ zone: String, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0
    ) -> Date {
        let calendar = calendar(zone)
        let components = DateComponents(
            timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour,
            minute: minute)
        return calendar.date(from: components) ?? .distantPast
    }

    /// One ordinary night in New York: evening activity, asleep 23:00–06:30, then up and moving.
    private func ordinaryNight(zone: String = "America/New_York") -> [MotionActivitySample] {
        [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 20), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 23), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 6, 30), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 7, 15), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 7, 40), quality: .high, kind: .automotive),
        ]
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

    /// The WG-313 regression: the same night read at two different times must not change. Before the
    /// fix the window was `[now - 10h, now]`, so opening later dropped the start of the night and
    /// swept in the morning's activity.
    func testSummaryIsIdenticalWhateverTimeTheScreenIsOpened() {
        let zone = "America/New_York"
        let samples = ordinaryNight()
        let early = summary(samples, at: local(zone, 2026, 5, 12, 7), zone: zone)
        let late = summary(samples, at: local(zone, 2026, 5, 12, 9), zone: zone)
        XCTAssertEqual(early.night, late.night, "the night is derived from the data, not the clock")
        XCTAssertEqual(early.disturbances, late.disturbances)
        XCTAssertEqual(early.rest, late.rest)
    }

    func testNightSpansTheAsleepStretchOnly() {
        let zone = "America/New_York"
        let resolved = summary(ordinaryNight(), at: local(zone, 2026, 5, 12, 9), zone: zone)
        XCTAssertEqual(resolved.night?.start, local(zone, 2026, 5, 11, 23))
        XCTAssertEqual(resolved.night?.end, local(zone, 2026, 5, 12, 6, 30))
        XCTAssertEqual(resolved.rest, 7.5 * 3_600, "the whole asleep stretch is the rest window")
    }

    func testMorningActivityAndCommuteDoNotCountAsOvernightPickups() {
        let zone = "America/New_York"
        let resolved = summary(ordinaryNight(), at: local(zone, 2026, 5, 12, 9), zone: zone)
        XCTAssertEqual(
            resolved.disturbances, SleepDisturbances.none,
            "getting up and driving happen after the night ends, so they are not disturbances")
    }

    func testBriefDisturbanceIsCountedInsideTheNightNotAsItsEnd() {
        let zone = "America/New_York"
        // Asleep 23:00, a 10-minute walk at 02:00, back to still until 06:30.
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 23), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 2), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 2, 10), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 6, 30), quality: .high, kind: .walking),
        ]
        let resolved = summary(samples, at: local(zone, 2026, 5, 12, 9), zone: zone)
        XCTAssertEqual(resolved.night?.start, local(zone, 2026, 5, 11, 23))
        XCTAssertEqual(resolved.night?.end, local(zone, 2026, 5, 12, 6, 30))
        XCTAssertEqual(resolved.disturbances?.pickups, 1, "a short wake-up sits inside the night")
        XCTAssertEqual(resolved.disturbances?.movingDuration, 600)
        XCTAssertEqual(
            resolved.rest, 4 * 3_600 + 20 * 60, "the longest single quiet run, not the whole night")
    }

    /// Getting up is rarely one long walk. A **segmented** commute — walk, drive, walk, each leg under
    /// `maxDisturbanceGap` — is one contiguous moving run and must end the night. Judging each sample
    /// span on its own instead absorbed the whole commute *into* the night.
    func testSegmentedCommuteEndsTheNightRatherThanSittingInsideIt() {
        let zone = "America/New_York"
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 23), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 6, 30), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 6, 45), quality: .high, kind: .automotive),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 7), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 7, 15), quality: .high, kind: .stationary),
        ]
        let resolved = summary(samples, at: local(zone, 2026, 5, 12, 9), zone: zone)
        XCTAssertEqual(resolved.night?.start, local(zone, 2026, 5, 11, 23))
        XCTAssertEqual(
            resolved.night?.end, local(zone, 2026, 5, 12, 6, 30), "the night ends when you get up")
        XCTAssertEqual(
            resolved.disturbances, SleepDisturbances.none,
            "a 45-minute commute in three legs is not an overnight disturbance")
    }

    /// A morning of short bursts *separated by sitting* never closes the night: every moving run really is
    /// brief and every sit really is quiet, structurally identical to a night with bathroom trips. No
    /// run-based rule can separate them.
    private func fragmentedMorning(zone: String) -> [MotionActivitySample] {
        [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 23), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 6, 30), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 6, 40), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 7, 10), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 7, 22), quality: .high, kind: .stationary),
        ]
    }

    /// **Known defect (WG-313 H2), not fixed.** The fragmented morning holds the night open indefinitely,
    /// and it keeps growing with every later read. Recorded as an expected failure so it is visible in CI
    /// and flips to a real failure the moment H2 lands.
    func testFragmentedMorningStillExtendsTheNight() {
        XCTExpectFailure(
            "WG-313 H2: a sedentary morning is indistinguishable from sleep by motion alone")
        let zone = "America/New_York"
        let samples = fragmentedMorning(zone: zone)
        let early = summary(samples, at: local(zone, 2026, 5, 12, 7, 30), zone: zone)
        let late = summary(samples, at: local(zone, 2026, 5, 12, 9), zone: zone)
        XCTAssertEqual(early.night, late.night, "the night must not grow as the morning goes on")
    }

    /// **Known defect (WG-313 H2), not fixed.** A desk-bound workday is quieter than the night that
    /// preceded it, so ranking candidate blocks by raw duration hands the "night" to the afternoon — and
    /// because that block runs to `now`, it grows every hour the screen is opened: the drift this task
    /// exists to remove, in daylight. This is the reproduction; it fails on all four assertions.
    ///
    /// A trailing validity cap (H3) was implemented and **reverted**, and it did turn this fixture green —
    /// but only because the desk period here holds exactly **one** record. Give the desk day a second
    /// record and the block is large again, so the fixture flattered the mechanism rather than pinning it.
    /// That is recorded in the WG-313 ADR; treat a green result on this test alone as insufficient.
    func testSedentaryDaytimeBlockDoesNotOutrankTheNight() {
        XCTExpectFailure("WG-313 H2: the longest merged block is chosen by raw duration")
        let zone = "America/New_York"
        // Asleep 23:00–06:30, a ninety-minute commute, then still at a desk from 08:00 onward.
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 23), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 6, 30), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 7), quality: .high, kind: .automotive),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 8), quality: .high, kind: .stationary),
        ]
        let afternoon = summary(samples, at: local(zone, 2026, 5, 12, 17), zone: zone)
        XCTAssertEqual(afternoon.night?.start, local(zone, 2026, 5, 11, 23))
        XCTAssertEqual(
            afternoon.night?.end, local(zone, 2026, 5, 12, 6, 30),
            "nine hours at a desk is quieter than the night, but it is not the night")
        XCTAssertEqual(afternoon.disturbances, SleepDisturbances.none)
        let evening = summary(samples, at: local(zone, 2026, 5, 12, 21), zone: zone)
        XCTAssertEqual(
            afternoon.night, evening.night, "the reported night must not grow as the day goes on")
        XCTAssertEqual(afternoon.rest, evening.rest)
    }

    /// **Known defect (WG-313 H2), open.** A block the data itself *closes* keeps its full length: nine
    /// hours still at a desk, ended by the walk home, outranks the broken night before it on raw duration.
    /// The reported night is then the desk, with **zero** disturbances — a false negative on precisely the
    /// signal this feature is named for, and worse than reporting nothing. This block is stable across
    /// reads, so the case isolates the **ranking** rule from the drift, and no cap on how far a sample is
    /// extrapolated can reach it. No wall-clock band either, without new evidence (see the WG-313 ADR).
    func testClosedSedentaryDaytimeBlockStillOutranksABrokenNight() {
        XCTExpectFailure("WG-313 H2: candidate blocks are still ranked by raw duration")
        let zone = "America/New_York"
        // A broken night — asleep 23:00 with two brief wake-ups — then the commute, a nine-hour desk
        // shift closed by the walk home at 17:00.
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 23), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 2), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 2, 15), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 4), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 4, 10), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 6, 30), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 7), quality: .high, kind: .automotive),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 8), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 17), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 17, 30), quality: .high, kind: .stationary),
        ]
        let resolved = summary(samples, at: local(zone, 2026, 5, 12, 20), zone: zone)
        XCTAssertEqual(resolved.night?.start, local(zone, 2026, 5, 11, 23))
        XCTAssertEqual(
            resolved.night?.end, local(zone, 2026, 5, 12, 6, 30),
            "nine hours at a desk is longer than the night, but it is not the night")
        XCTAssertEqual(
            resolved.disturbances?.pickups, 2,
            "the two wake-ups are the answer the user came for; the desk reports none")
    }

    func testNoSustainedQuietStretchIsUnavailableNotFabricated() {
        let zone = "America/New_York"
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 20), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 5), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 5, 20), quality: .high, kind: .walking),
        ]
        let resolved = summary(samples, at: local(zone, 2026, 5, 12, 9), zone: zone)
        XCTAssertNil(resolved.night, "a 20-minute lull is not a night; report unavailable")
        XCTAssertNil(resolved.disturbances)
    }

    func testCandidateSpanAnchorsToThePreviousLocalEvening() {
        let zone = "America/New_York"
        let span = SleepDisturbanceEstimator.candidateSpan(
            endingAt: local(zone, 2026, 5, 12, 9), calendar: calendar(zone))
        XCTAssertEqual(span.start, local(zone, 2026, 5, 11, 18))
        XCTAssertEqual(span.end, local(zone, 2026, 5, 12, 9))
    }

    /// The anchor is a **local wall-clock** hour, so the spring-forward night (02:00 → 03:00 EST→EDT)
    /// still anchors at 18:00 local, and the elapsed night is one hour shorter in absolute time.
    func testSpringForwardNightAnchorsAtLocalEveningAndMeasuresElapsedTime() {
        let zone = "America/New_York"
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 3, 7, 23), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 3, 8, 7), quality: .high, kind: .walking),
        ]
        let resolved = summary(samples, at: local(zone, 2026, 3, 8, 9), zone: zone)
        XCTAssertEqual(resolved.night?.start, local(zone, 2026, 3, 7, 23))
        XCTAssertEqual(
            resolved.rest, 7 * 3_600,
            "23:00→07:00 across spring-forward is seven elapsed hours, not eight")
    }

    /// Travelling changes the anchor's zone, but the night is still found from the samples — the
    /// estimate stays available rather than collapsing.
    func testNightIsStillResolvedAfterATimeZoneChange() {
        // Slept on Tokyo wall-clock time, opened the app after landing in New York.
        let samples = [
            MotionActivitySample(
                timestamp: local("Asia/Tokyo", 2026, 5, 12, 23), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local("Asia/Tokyo", 2026, 5, 13, 6), quality: .high, kind: .walking),
        ]
        let resolved = summary(
            samples, at: local("Asia/Tokyo", 2026, 5, 13, 8), zone: "America/New_York")
        XCTAssertNotNil(resolved.night, "a real quiet stretch is still found in the new zone")
        XCTAssertEqual(resolved.rest, 7 * 3_600)
    }
}
