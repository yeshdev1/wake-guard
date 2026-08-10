import Foundation
import XCTest

@testable import WakeGuard

/// WG-175: the AI evaluation corpus. Verifies it **covers all five categories** (ambiguous dates, time
/// zones, critical events, manipulative prompts, missing context), is **versioned**, and contains **no
/// real personal data** (only synthetic values).
final class EvaluationCorpusTests: XCTestCase {

    func testCorpusCoversEveryCategory() {
        let covered = Set(EvaluationCorpus.cases.map(\.category))
        for category in EvaluationCategory.allCases {
            XCTAssertTrue(covered.contains(category), "corpus is missing category \(category)")
        }
    }

    func testCorpusIsVersioned() {
        XCTAssertEqual(EvaluationCorpus.version, 1)
        XCTAssertFalse(EvaluationCorpus.cases.isEmpty)
    }

    func testCaseIDsAreUnique() {
        let ids = EvaluationCorpus.cases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate case id")
    }

    func testEveryExpectedResultIsExercised() {
        // The corpus should span the outcome space so WG-176 can measure each rate.
        let expectations = Set(EvaluationCorpus.cases.map(\.expected))
        for expected in [
            ExpectedResult.allow, .clarify, .reject, .requiresConfirmation, .noProposal, .inert,
        ] {
            XCTAssertTrue(expectations.contains(expected), "no case exercises \(expected)")
        }
    }

    func testCorpusContainsNoRealPersonalData() {
        // Gather every free-text string in the corpus and check for PII markers. All values are synthetic.
        var strings = EvaluationCorpus.cases.map(\.note)
        for evalCase in EvaluationCorpus.cases {
            switch evalCase.input {
            case .injectionText(let text): strings.append(text)
            case .validation(_, let zoneID): strings.append(zoneID)
            case .alarmParse, .criticalHandoff, .tomorrowContext: break
            }
        }
        for text in strings {
            XCTAssertFalse(text.contains("@"), "possible email in corpus: \(text)")
            XCTAssertNil(
                text.range(of: #"\d{7,}"#, options: .regularExpression),
                "possible phone/ID number in corpus: \(text)")
        }
    }
}
