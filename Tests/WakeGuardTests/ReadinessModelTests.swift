import Foundation
import XCTest

@testable import WakeGuard

/// WG-125: the readiness factor model. Verifies **factors and contributions are deterministic** (pure,
/// documented formulas, recomputable from the factors — no black box), that **missing factors reduce
/// certainty** (not the score), and that it is an explainable estimate with **no black-box diagnosis**.
final class ReadinessModelTests: XCTestCase {

    private let hour: TimeInterval = 3_600

    private func inputs(
        asleep: TimeInterval? = nil, deviationMinutes: Double? = nil, debt: TimeInterval? = nil,
        need: TimeInterval = 8 * 3_600
    ) -> ReadinessInputs {
        ReadinessInputs(
            lastNightAsleep: asleep,
            consistency: deviationMinutes.map {
                SleepConsistency(
                    typicalMidpointSecondsOfDay: 0, meanDeviationMinutes: $0, nights: 3)
            },
            debt: debt.map {
                SleepDebtEstimate(
                    debt: $0, sleepNeed: need, nightsCounted: 3, nightsMissing: 0, wasCapped: false)
            },
            need: SleepNeed(perNight: need))
    }

    // MARK: deterministic factors + contributions

    func testFullyRestedGivesGoodReadinessAtHighCertainty() throws {
        let assessment = ReadinessModel.assess(
            inputs(asleep: 8 * hour, deviationMinutes: 0, debt: 0))
        XCTAssertEqual(assessment.factors.count, 3)
        XCTAssertEqual(try XCTUnwrap(assessment.weightedScore), 1, accuracy: 0.0001)
        XCTAssertEqual(assessment.level, .good)
        XCTAssertEqual(assessment.certainty, .high)
    }

    func testAssessmentIsDeterministic() {
        let input = inputs(asleep: 6 * hour, deviationMinutes: 30, debt: 2 * hour)
        XCTAssertEqual(ReadinessModel.assess(input), ReadinessModel.assess(input))
    }

    func testFactorContributionFormulasAreTransparent() {
        XCTAssertEqual(
            ReadinessModel.durationScore(8 * hour, need: SleepNeed(perNight: 8 * hour)), 1,
            accuracy: 0.0001)
        XCTAssertEqual(
            ReadinessModel.durationScore(4 * hour, need: SleepNeed(perNight: 8 * hour)), 0.5,
            accuracy: 0.0001)
        XCTAssertEqual(
            ReadinessModel.durationScore(12 * hour, need: SleepNeed(perNight: 8 * hour)), 1,
            accuracy: 0.0001,
            "clamped at 1")
        XCTAssertEqual(consistencyScore(0), 1, accuracy: 0.0001)
        XCTAssertEqual(consistencyScore(60), 0.5, accuracy: 0.0001)
        XCTAssertEqual(consistencyScore(200), 0, accuracy: 0.0001, "clamped at 0")
        XCTAssertEqual(debtScore(0), 1, accuracy: 0.0001)
        XCTAssertEqual(debtScore(12 * hour), 0.5, accuracy: 0.0001)  // 1.5 nights of an 8h need
        XCTAssertEqual(debtScore(24 * hour), 0, accuracy: 0.0001)  // 3 nights → floor
    }

    private func consistencyScore(_ deviation: Double) -> Double {
        ReadinessModel.consistencyScore(
            SleepConsistency(
                typicalMidpointSecondsOfDay: 0, meanDeviationMinutes: deviation, nights: 3))
    }

    private func debtScore(_ debt: TimeInterval) -> Double {
        ReadinessModel.debtScore(
            SleepDebtEstimate(
                debt: debt, sleepNeed: 8 * hour, nightsCounted: 3, nightsMissing: 0,
                wasCapped: false))
    }

    // MARK: missing factors reduce certainty (not the score)

    func testMissingFactorsReduceCertainty() {
        XCTAssertEqual(
            ReadinessModel.assess(inputs(asleep: 8 * hour, deviationMinutes: 0, debt: 0)).certainty,
            .high)
        XCTAssertEqual(
            ReadinessModel.assess(inputs(asleep: 8 * hour, deviationMinutes: 0)).certainty,
            .moderate)
        XCTAssertEqual(ReadinessModel.assess(inputs(asleep: 8 * hour)).certainty, .low)
    }

    func testNoFactorsIsUnavailableNotFabricated() {
        let assessment = ReadinessModel.assess(inputs())
        XCTAssertTrue(assessment.factors.isEmpty)
        XCTAssertNil(
            assessment.weightedScore, "no data → unavailable, never a fabricated readiness")
        XCTAssertNil(assessment.level)
        XCTAssertEqual(assessment.certainty, .low)
    }

    func testAMissingFactorLowersCertaintyNotTheScore() throws {
        // Only last night present, at half the need → the score reflects that one factor (0.5), it is not
        // dragged toward 0 by the missing factors; certainty is low instead.
        let assessment = ReadinessModel.assess(inputs(asleep: 4 * hour))
        XCTAssertEqual(try XCTUnwrap(assessment.weightedScore), 0.5, accuracy: 0.0001)
        XCTAssertEqual(assessment.certainty, .low)
    }

    // MARK: no black-box — the score is recomputable from the factors

    func testWeightedScoreIsRecomputableFromTheFactors() throws {
        let assessment = ReadinessModel.assess(
            inputs(asleep: 6 * hour, deviationMinutes: 30, debt: 2 * hour))
        let totalWeight = assessment.factors.reduce(0) { $0 + $1.weight }
        let manual = assessment.factors.reduce(0) { $0 + $1.contribution * $1.weight } / totalWeight
        XCTAssertEqual(try XCTUnwrap(assessment.weightedScore), manual, accuracy: 0.0001)
    }

    // MARK: level thresholds are fixed + deterministic

    func testLevelThresholds() {
        XCTAssertEqual(level(0.75), .good)
        XCTAssertEqual(level(0.74), .moderate)
        XCTAssertEqual(level(0.5), .moderate)
        XCTAssertEqual(level(0.49), .low)
    }

    private func level(_ score: Double) -> ReadinessLevel? {
        ReadinessAssessment(
            factors: [ReadinessFactor(kind: .sleepDuration, contribution: score, weight: 1)],
            certainty: .low
        ).level
    }
}
