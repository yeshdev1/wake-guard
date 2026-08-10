import XCTest

@testable import WakeGuard

/// WG-126: the readiness explanation. Verifies **every statement maps to a recorded factor** (no
/// ungrounded claim), that **uncertainty and missing inputs display**, and that the **copy is
/// nonjudgmental** (and never a diagnosis, #39).
final class ReadinessExplanationTests: XCTestCase {

    private func factor(_ kind: ReadinessFactorKind, _ contribution: Double) -> ReadinessFactor {
        ReadinessFactor(kind: kind, contribution: contribution, weight: 1)
    }

    // MARK: every statement maps to a recorded factor

    func testEveryFactorStatementMapsToARecordedFactor() {
        let assessment = ReadinessAssessment(
            factors: [
                factor(.sleepDuration, 0.9), factor(.sleepConsistency, 0.9),
                factor(.sleepDebt, 0.9),
            ],
            certainty: .high)
        let explanation = ReadinessExplanation.from(assessment)
        XCTAssertEqual(
            Set(explanation.factorStatements.map(\.factor)), Set(assessment.factors.map(\.kind)))
        XCTAssertTrue(
            Set(explanation.factorStatements.map(\.factor)).isDisjoint(
                with: Set(explanation.missingInputs)),
            "no statement is made about a factor we have no data for")
    }

    // MARK: uncertainty + missing inputs display

    func testMissingInputsAreSurfaced() {
        let assessment = ReadinessAssessment(
            factors: [factor(.sleepDuration, 0.9)], certainty: .low)
        let explanation = ReadinessExplanation.from(assessment)
        XCTAssertEqual(explanation.factorStatements.map(\.factor), [.sleepDuration])
        XCTAssertEqual(explanation.missingInputs, [.sleepConsistency, .sleepDebt])
    }

    func testCertaintyNoteReflectsCertainty() {
        XCTAssertTrue(note(.high, [.sleepDuration]).contains("Based on your recent sleep"))
        XCTAssertTrue(note(.moderate, [.sleepDuration]).lowercased().contains("some"))
        XCTAssertTrue(note(.low, [.sleepDuration]).lowercased().contains("rough guess"))
        XCTAssertTrue(note(.low, []).lowercased().contains("add"), "no data → invites adding data")
    }

    private func note(_ certainty: ReadinessCertainty, _ kinds: [ReadinessFactorKind]) -> String {
        ReadinessExplanation.from(
            ReadinessAssessment(factors: kinds.map { factor($0, 0.9) }, certainty: certainty)
        ).certaintyNote
    }

    func testNoDataAssessmentIsHonest() {
        let explanation = ReadinessExplanation.from(
            ReadinessAssessment(factors: [], certainty: .low))
        XCTAssertTrue(explanation.summary.lowercased().contains("isn't enough sleep data"))
        XCTAssertTrue(explanation.factorStatements.isEmpty)
        XCTAssertEqual(explanation.missingInputs, ReadinessFactorKind.allCases)
    }

    // MARK: copy is nonjudgmental (and no medical claim)

    func testAllCopyIsNonjudgmentalAndMakesNoMedicalClaim() {
        // Collect every string the builder can produce, across levels, certainties, and both contribution
        // bands of every factor.
        var texts: [String] = []
        for level in [0.9, 0.2] {
            let assessment = ReadinessAssessment(
                factors: ReadinessFactorKind.allCases.map { factor($0, level) }, certainty: .high)
            let explanation = ReadinessExplanation.from(assessment)
            texts.append(explanation.summary)
            texts.append(contentsOf: explanation.factorStatements.map(\.text))
        }
        for certainty in ReadinessCertainty.allCases {
            texts.append(note(certainty, [.sleepDuration]))
        }
        texts.append(note(.low, []))  // the no-data summary + note

        let banned = [
            "bad", "poor", "terrible", "fail", "lazy", "should", "must ", "guilt", "shame",
            "diagnose", "disorder", "treatment", "deprivation",
        ]
        let corpus = texts.joined(separator: " ").lowercased()
        for token in banned {
            XCTAssertFalse(
                corpus.contains(token), "copy must stay nonjudgmental / non-medical: \(token)")
        }
    }

    func testFactorStatementDiffersByContributionBand() {
        let rested = ReadinessExplanation.from(
            ReadinessAssessment(factors: [factor(.sleepDuration, 0.95)], certainty: .low))
        let short = ReadinessExplanation.from(
            ReadinessAssessment(factors: [factor(.sleepDuration, 0.3)], certainty: .low))
        XCTAssertNotEqual(
            rested.factorStatements.first?.text, short.factorStatements.first?.text,
            "the statement reflects the factor's contribution")
    }
}
