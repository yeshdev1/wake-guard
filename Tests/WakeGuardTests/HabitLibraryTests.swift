import XCTest

@testable import WakeGuard

/// WG-127: the evidence-based habit suggestion library. Verifies suggestions are **static/curated**, make
/// **no treatment claims** (#39), and that **contraindication-sensitive** suggestions are **excluded** —
/// both structurally (the safety tag + accessor filter) and by content (no supplement/medication topics).
final class HabitLibraryTests: XCTestCase {

    private func factor(_ kind: ReadinessFactorKind, _ contribution: Double) -> ReadinessFactor {
        ReadinessFactor(kind: kind, contribution: contribution, weight: 1)
    }

    private var corpus: String {
        HabitLibrary.curated
            .flatMap { [$0.headline, $0.detail, $0.evidenceNote] }
            .joined(separator: " ").lowercased()
    }

    // MARK: curated + well-formed

    func testCuratedLibraryIsNonEmptyAndWellFormed() {
        XCTAssertFalse(HabitLibrary.curated.isEmpty)
        for suggestion in HabitLibrary.curated {
            XCTAssertFalse(suggestion.headline.isEmpty, "\(suggestion.id) needs a headline")
            XCTAssertFalse(suggestion.detail.isEmpty, "\(suggestion.id) needs detail")
            XCTAssertFalse(
                suggestion.evidenceNote.isEmpty, "\(suggestion.id) needs an evidence note")
        }
        let ids = HabitLibrary.curated.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ids are unique")
    }

    // MARK: contraindication-sensitive suggestions are excluded

    func testCuratedLibraryIsAllGenerallySafe() {
        XCTAssertTrue(
            HabitLibrary.curated.allSatisfy { $0.safety == .generallySafe },
            "the curated library contains no contraindication-sensitive suggestion")
    }

    func testCuratedContentAvoidsContraindicatedTopics() {
        let banned = [
            "supplement", "melatonin", "medication", "medicine", "pill", "drug", "alcohol",
            "caffeine", "fasting", "vigorous", "cbd", "herbal", "dose",
        ]
        for token in banned {
            XCTAssertFalse(
                corpus.contains(token), "a curated tip references a sensitive topic: \(token)")
        }
    }

    func testTheAccessorFiltersOutAContraindicationSensitiveEntry() {
        // Even if a sensitive suggestion were ever added to a list, the accessor must not surface it.
        let sensitive = HabitSuggestion(
            id: "sensitive", factor: .sleepDuration, headline: "x", detail: "x", evidenceNote: "x",
            safety: .contraindicationSensitive)
        let result = HabitLibrary.suggestions(
            for: .sleepDuration, from: HabitLibrary.curated + [sensitive])
        XCTAssertFalse(
            result.contains(sensitive), "contraindication-sensitive entries are excluded")
        XCTAssertTrue(result.allSatisfy { $0.safety == .generallySafe })
    }

    // MARK: no treatment claims (#39)

    func testNoSuggestionMakesATreatmentClaim() {
        let banned = [
            "treat", "cure", "prevent", "diagnos", "disorder", "therapy", "disease", "insomnia",
        ]
        for token in banned {
            XCTAssertFalse(
                corpus.contains(token), "a curated tip makes a treatment/medical claim: \(token)")
        }
    }

    // MARK: relevance

    func testSuggestionsForAFactorReturnOnlyThatFactorsSafeTips() {
        let tips = HabitLibrary.suggestions(for: .sleepConsistency)
        XCTAssertFalse(tips.isEmpty)
        XCTAssertTrue(
            tips.allSatisfy { $0.factor == .sleepConsistency && $0.safety == .generallySafe })
    }

    func testSuggestionsForAnAssessmentTargetOnlyBelowParFactors() {
        // Consistency is below par (0.3), duration is fine (0.9) → only consistency tips are offered.
        let assessment = ReadinessAssessment(
            factors: [factor(.sleepConsistency, 0.3), factor(.sleepDuration, 0.9)],
            certainty: .moderate)
        let tips = HabitLibrary.suggestions(for: assessment)
        XCTAssertFalse(tips.isEmpty)
        XCTAssertTrue(
            tips.allSatisfy { $0.factor == .sleepConsistency },
            "only the below-par factor's tips are offered")
    }

    func testAnAllRestedAssessmentOffersNoTips() {
        let assessment = ReadinessAssessment(
            factors: ReadinessFactorKind.allCases.map { factor($0, 0.95) }, certainty: .high)
        XCTAssertTrue(
            HabitLibrary.suggestions(for: assessment).isEmpty, "nothing to nudge when rested")
    }
}
