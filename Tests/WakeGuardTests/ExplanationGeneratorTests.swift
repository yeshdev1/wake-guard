import Foundation
import XCTest

@testable import WakeGuard

/// WG-169: the explanation generator. Verifies **every claim cites an internal factor ID**, that
/// **unsupported claims are dropped** (a claim citing an unknown factor never survives), and that a
/// **deterministic template fallback** produces a grounded explanation when the model is unavailable or
/// every claim is ungrounded.
final class ExplanationGeneratorTests: XCTestCase {

    private let factors = [
        ExplanationFactor(id: "readiness", value: "good"),
        ExplanationFactor(id: "sleepDebt", value: "mild"),
    ]

    private func generator(_ output: String) -> ExplanationGenerator {
        ExplanationGenerator(
            generator: StructuredGenerator(
                provider: ScriptedLanguageModelProvider.returning(output)))
    }

    // MARK: every surviving claim is grounded; unsupported claims are dropped

    func testUnsupportedClaimsAreDroppedAndSurvivorsAreGrounded() async {
        let json = #"""
            {"claims":[
              {"factorID":"readiness","claim":"You slept well."},
              {"factorID":"totallyMadeUp","claim":"Mercury is in retrograde."}
            ]}
            """#
        let explanation = await generator(json).explain(factors: factors)
        XCTAssertFalse(explanation.usedFallback)
        XCTAssertEqual(explanation.statements.map(\.factorID), ["readiness"])
        let known = Set(factors.map(\.id))
        for statement in explanation.statements {
            XCTAssertTrue(known.contains(statement.factorID), "every claim must cite a real factor")
        }
    }

    // MARK: deterministic template fallback

    func testAllUngroundedClaimsFallBackToTemplate() async {
        let json = #"{"claims":[{"factorID":"ghost","claim":"Boo."}]}"#
        let explanation = await generator(json).explain(factors: factors)
        XCTAssertTrue(explanation.usedFallback)
        XCTAssertEqual(explanation.statements.map(\.factorID), ["readiness", "sleepDebt"])
    }

    func testModelFailureFallsBackToTemplate() async {
        let failing = ExplanationGenerator(
            generator: StructuredGenerator(
                provider: ScriptedLanguageModelProvider.failing(.refused)))
        let explanation = await failing.explain(factors: factors)
        XCTAssertTrue(explanation.usedFallback)
        XCTAssertEqual(explanation.statements.count, factors.count)
    }

    func testTemplateFallbackIsDeterministicAndGrounded() {
        let first = ExplanationGenerator.fallback(for: factors)
        let second = ExplanationGenerator.fallback(for: factors)
        XCTAssertEqual(first, second)
        let known = Set(factors.map(\.id))
        for statement in first.statements {
            XCTAssertTrue(known.contains(statement.factorID))
            XCTAssertTrue(statement.text.contains(statement.factorID))
        }
    }

    // MARK: edges

    func testNoFactorsYieldsAnEmptyExplanation() async {
        let explanation = await generator(#"{"claims":[]}"#).explain(factors: [])
        XCTAssertTrue(explanation.isEmpty)
    }

    func testEmptyClaimsFallBackToTemplate() async {
        let explanation = await generator(#"{"claims":[]}"#).explain(factors: factors)
        XCTAssertTrue(explanation.usedFallback)
        XCTAssertFalse(explanation.isEmpty)
    }

    // MARK: statements are inert (no command)

    func testStatementHasNoCommandField() {
        let statement = GroundedStatement(factorID: "readiness", text: "x")
        let fields = Set(Mirror(reflecting: statement).children.compactMap(\.label))
        XCTAssertEqual(fields, ["factorID", "text"])
        XCTAssertFalse(fields.contains("command"))
    }
}
