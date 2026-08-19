import Foundation
import XCTest

@testable import WakeGuard

/// WG-313 H3: how far a motion sample's classification may be **extrapolated** — open, not fixed.
///
/// The estimator reads each sample as classifying the timeline until the next sample, and the last sample
/// as classifying everything up to the window's end. Silence is therefore read as stillness, which
/// fabricates nights the data does not evidence. The fabrications are carried here as `XCTExpectFailure`
/// reproductions so they stay visible in CI.
///
/// The **passing** tests in this file are the constraint set: they are what a trailing-only validity cap
/// broke when it was tried, and they are why it was reverted (see the WG-313 ADR). Any future attempt must
/// keep them green.
final class SleepDisturbanceSampleValidityTests: XCTestCase {

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZone = TimeZone(identifier: zone) { calendar.timeZone = timeZone }
        return calendar
    }

    /// Builds an instant from local wall-clock components in `zone`. The identifiers and components here
    /// are all valid, so the fallback is unreachable — any slip would fail the assertions loudly.
    private func local(
        _ zone: String, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0
    ) -> Date {
        let calendar = calendar(zone)
        let components = DateComponents(
            timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour,
            minute: minute)
        return calendar.date(from: components) ?? .distantPast
    }

    /// The night as `ReadinessViewModel` resolves it: the previous-evening candidate span, then the
    /// data-derived night within it.
    private func night(_ samples: [MotionActivitySample], at now: Date, zone: String)
        -> DateInterval?
    {
        let span = SleepDisturbanceEstimator.candidateSpan(endingAt: now, calendar: calendar(zone))
        return SleepDisturbanceEstimator.nightSpan(samples: samples, in: span)
    }

    private let zone = "America/New_York"

    // MARK: - Fabrication (H3, open)

    /// **Known defect (WG-313 H3), not fixed.** One `.stationary` record early in the evening and nothing
    /// afterwards. The device may have been still all night — or powered off at 18:31; the history query
    /// returns no records either way, so the two are indistinguishable. Extending the record to `now` picks
    /// the flattering reading and reports a 14.5-hour night from a single data point.
    func testASingleStaleStationarySampleDoesNotFabricateANight() {
        XCTExpectFailure("WG-313 H3: the last sample's classification runs to the window end")
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 18, 30), quality: .high, kind: .stationary)
        ]
        XCTAssertNil(
            night(samples, at: local(zone, 2026, 5, 12, 9), zone: zone),
            "one record and 14.5 hours of silence is not a night; report unavailable")
    }

    /// **Known defect (WG-313 H3), not fixed.** `.unknown` is the classifier saying it has **no confident
    /// classification**, and the estimator counts it as quiet. Extrapolating an explicit non-classification
    /// across a whole span is the strongest form of the same fabrication.
    func testASingleUnknownSampleDoesNotFabricateANight() {
        XCTExpectFailure("WG-313 H3: an unconfident classification is extended like any other")
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 19), quality: .low, kind: .unknown)
        ]
        XCTAssertNil(
            night(samples, at: local(zone, 2026, 5, 12, 9), zone: zone),
            "an unconfident classification extended for 14 hours is not evidence of a night")
    }

    /// **Known defect (WG-313 H3), not fixed — and the reason a trailing-only cap is not the answer.** The
    /// gap here is *interior*, between two records, so no cap on the trailing sample touches it: a phone
    /// switched off after the evening walk and switched on in the morning reports a fifteen-hour
    /// undisturbed night. Any real fix has to reason about evidence coverage, not just about the tail.
    func testAnInteriorGapWithNoRecordsDoesNotFabricateANight() {
        XCTExpectFailure("WG-313 H3: an interior gap is extrapolated as freely as a trailing one")
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 17, 50), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 18, 5), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 9), quality: .high, kind: .walking),
        ]
        XCTAssertNil(
            night(samples, at: local(zone, 2026, 5, 12, 10), zone: zone),
            "fifteen hours with no records at all is not an observed night")
    }

    /// **Known defect (WG-313 H3), not fixed.** Until something closes the night, its end is `now`, so the
    /// reported rest keeps growing across reads — the drift WG-313 exists to remove, in its last remaining
    /// form.
    func testAnUnclosedNightStillGrowsWithEveryRead() {
        XCTExpectFailure("WG-313 H3: an unclosed block ends at the window end, which is `now`")
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 23), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 5), quality: .high, kind: .stationary),
        ]
        XCTAssertEqual(
            night(samples, at: local(zone, 2026, 5, 12, 12), zone: zone),
            night(samples, at: local(zone, 2026, 5, 12, 15), zone: zone),
            "an unclosed night must not keep growing with every later read")
    }

    // MARK: - The constraint set a fix must not break

    /// Between two records the earlier classification holds — that is CoreMotion's contract, and a real
    /// night *is* one `.stationary` record followed hours later by a `.walking` one. A validity cap applied
    /// to the gap rather than the tail deletes every genuine night; when this was tried it failed here
    /// first.
    func testAQuietGapBetweenTwoRecordsStillResolvesTheWholeNight() {
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 23), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 12, 6, 30), quality: .high, kind: .walking),
        ]
        let resolved = night(samples, at: local(zone, 2026, 5, 12, 9), zone: zone)
        XCTAssertEqual(resolved?.start, local(zone, 2026, 5, 11, 23))
        XCTAssertEqual(
            resolved?.end, local(zone, 2026, 5, 12, 6, 30),
            "seven and a half hours between two records is the night, not a gap to be capped")
    }

    /// An evening on the sofa is **closed** by the walk to bed, so it keeps its full length; the night that
    /// follows is still open. Shortening open blocks — which is what a trailing cap does — lets the sofa
    /// outrank the bed, and an eight-hour sleeper is told "2h 30m of low activity overnight". A wrong
    /// number stated confidently is worse than the `nil` such a fix is meant to prefer.
    func testAnEveningOnTheSofaMustNotOutrankAnUnclosedNight() {
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 18, 30), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 19), quality: .high, kind: .stationary),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 21, 30), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 23), quality: .high, kind: .stationary),
        ]
        XCTAssertEqual(
            night(samples, at: local(zone, 2026, 5, 12, 7), zone: zone)?.start,
            local(zone, 2026, 5, 11, 23),
            "two and a half hours on the sofa is not the night that followed it")
    }

    /// The user wakes and opens the app before walking anywhere, so no record has closed the night yet.
    /// The section must still resolve — this is the moment an alarm app exists for, and hiding the section
    /// there is indistinguishable from denied access to the user.
    func testAStillSleeperWhoHasNotMovedYetStillGetsANight() {
        let samples = [
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 21), quality: .high, kind: .walking),
            MotionActivitySample(
                timestamp: local(zone, 2026, 5, 11, 23), quality: .high, kind: .stationary),
        ]
        XCTAssertNotNil(
            night(samples, at: local(zone, 2026, 5, 12, 7), zone: zone),
            "eight hours still in bed is a night, even before the first step of the morning")
    }
}
