import Foundation
import XCTest

@testable import WakeGuard

/// WG-124: conservative sleep-debt estimate. Verifies the **sleep need is configurable** (clamped to a
/// sane range), the **estimate explains its assumptions**, and **no medical claim is made** — plus the
/// conservative behaviour (surplus offsets, floored at 0, capped) and that missing data is excluded, not
/// fabricated.
final class SleepDebtTests: XCTestCase {

    private let hour: TimeInterval = 3_600

    // MARK: sleep need is configurable

    func testSleepNeedIsConfigurableAndClampedToASaneRange() {
        XCTAssertEqual(SleepNeed.default.perNight, 8 * 3_600)
        XCTAssertEqual(
            SleepNeed(perNight: 7 * 3_600).perNight, 7 * 3_600, "a normal value is honored")
        XCTAssertEqual(
            SleepNeed(perNight: 1 * 3_600).perNight, SleepNeed.minimum, "too-low clamps up")
        XCTAssertEqual(
            SleepNeed(perNight: 20 * 3_600).perNight, SleepNeed.maximum, "too-high clamps down")
        XCTAssertEqual(
            SleepNeed(perNight: .nan).perNight, 8 * 3_600, "non-finite falls back to default")
    }

    // MARK: conservative behaviour

    func testDebtSumsNightlyShortfallsBelowNeed() throws {
        // 3 nights, each 2 h short of an 8 h need → 6 h debt.
        let estimate = try XCTUnwrap(
            SleepDebt.estimate(
                nightlyDurations: [6 * hour, 6 * hour, 6 * hour],
                need: SleepNeed(perNight: 8 * hour)))
        XCTAssertEqual(estimate.debt, 6 * hour)
        XCTAssertEqual(estimate.nightsCounted, 3)
        XCTAssertFalse(estimate.wasCapped)
    }

    func testSurplusNightsOffsetPriorShortfall() throws {
        // −2h, −2h, then +3h recovery → net 1 h debt.
        let estimate = try XCTUnwrap(
            SleepDebt.estimate(
                nightlyDurations: [6 * hour, 6 * hour, 11 * hour],
                need: SleepNeed(perNight: 8 * hour)))
        XCTAssertEqual(estimate.debt, 1 * hour)
    }

    func testNetSurplusFloorsDebtAtZero() throws {
        let estimate = try XCTUnwrap(
            SleepDebt.estimate(
                nightlyDurations: [9 * hour, 9 * hour], need: SleepNeed(perNight: 8 * hour)))
        XCTAssertEqual(estimate.debt, 0, "a well-rested stretch shows no debt, never negative")
    }

    func testDebtIsCappedAtAConservativeCeiling() throws {
        // A pathological run of zero-sleep nights must not imply an unbounded deficit.
        let estimate = try XCTUnwrap(
            SleepDebt.estimate(
                nightlyDurations: Array(repeating: 0, count: 30),
                need: SleepNeed(perNight: 8 * hour),
                maxNights: 7))
        XCTAssertEqual(estimate.debt, 8 * hour * 7, "capped at need x maxNights")
        XCTAssertTrue(estimate.wasCapped)
    }

    // MARK: missing data is excluded, not fabricated

    func testMissingNightsAreExcludedNotAssumed() throws {
        let estimate = try XCTUnwrap(
            SleepDebt.estimate(
                nightlyDurations: [6 * hour, nil, nil, 6 * hour],
                need: SleepNeed(perNight: 8 * hour)))
        XCTAssertEqual(estimate.nightsCounted, 2)
        XCTAssertEqual(estimate.nightsMissing, 2)
        XCTAssertEqual(estimate.debt, 4 * hour, "only the two nights with data count")
    }

    func testNoDataIsUnavailable() {
        XCTAssertNil(SleepDebt.estimate(nightlyDurations: [], need: .default))
        XCTAssertNil(
            SleepDebt.estimate(nightlyDurations: [nil, nil], need: .default), "never a fake 0")
    }

    // MARK: explains assumptions + no medical claim (#39)

    func testAssumptionsExplainTheEstimateAndMakeNoMedicalClaim() throws {
        let estimate = try XCTUnwrap(
            SleepDebt.estimate(
                nightlyDurations: [6 * hour, nil], need: SleepNeed(perNight: 8 * hour)))
        let text = estimate.assumptions.joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("sleep need"), "explains the configurable need")
        XCTAssertTrue(text.contains("excluded"), "explains missing nights are excluded")
        XCTAssertTrue(text.contains("recovery"), "explains surplus offsets")
        XCTAssertTrue(text.contains("not a diagnosis"), "carries the no-medical-claim disclaimer")
        for token in ["diagnose", "treatment", "disorder", "cure "] {
            XCTAssertFalse(text.contains(token), "must make no medical claim: \(token)")
        }
    }

    func testHoursTextFormatsWholeAndPartialHours() {
        XCTAssertEqual(SleepDebtEstimate.hoursText(8 * hour), "8h")
        XCTAssertEqual(SleepDebtEstimate.hoursText(7 * hour + 30 * 60), "7h 30m")
    }
}
