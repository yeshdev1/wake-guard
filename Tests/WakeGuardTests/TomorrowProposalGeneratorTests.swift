import Foundation
import XCTest

@testable import WakeGuard

/// WG-168: Tomorrow Agent proposal generation. Verifies the output is a **bounded proposal, not a command**
/// (no command/criticality field, no authority), that **reasons reference actual factors** (fabricated or
/// not-in-context citations are dropped, and a proposal with none is refused), and that a **critical**
/// target flags `requiresConfirmation`. Also pins the deterministic safety bound: never suggest waking
/// later than the latest safe wake.
final class TomorrowProposalGeneratorTests: XCTestCase {

    private func context(includeLatestSafeWake: Bool = true) -> TomorrowContext {
        var factors = [TomorrowFactor(id: .readiness, value: "good")]
        if includeLatestSafeWake {
            factors.append(TomorrowFactor(id: .latestSafeWake, value: "06:45"))
        }
        return TomorrowContext(factors: factors, unavailableSources: [])
    }

    private func draft(
        hour: Int, minute: Int = 0, grounded: [String], rationale: String = "Rested."
    ) -> AITomorrowPlanProposal {
        AITomorrowPlanProposal(
            suggestedWakeHour: hour, suggestedWakeMinute: minute, groundedFactorIDs: grounded,
            rationale: rationale)
    }

    // MARK: bounded proposal, grounded in real factors

    func testValidDraftBecomesAGroundedProposal() throws {
        let outcome = TomorrowProposalGenerator.interpret(
            draft(hour: 6, minute: 30, grounded: ["readiness"]), context: context(),
            targetIsCritical: false)
        guard case .proposal(let proposal) = outcome else { return XCTFail("expected proposal") }
        XCTAssertEqual(proposal.suggestedWake, try TimeOfDay(hour: 6, minute: 30))
        XCTAssertEqual(proposal.groundedFactors, [.readiness])
        XCTAssertFalse(proposal.requiresConfirmation)
    }

    func testFabricatedCitationsAreDropped() {
        let outcome = TomorrowProposalGenerator.interpret(
            draft(hour: 6, minute: 0, grounded: ["readiness", "totallyMadeUp", "readiness"]),
            context: context(), targetIsCritical: false)
        guard case .proposal(let proposal) = outcome else { return XCTFail("expected proposal") }
        XCTAssertEqual(
            proposal.groundedFactors, [.readiness], "unknown + duplicate citations removed")
    }

    func testCitationOfAFactorNotInContextIsRefused() {
        // `sleepDebt` is a real factor ID but absent from this context — a proposal citing only it has no
        // actual grounding, so it is refused.
        let outcome = TomorrowProposalGenerator.interpret(
            draft(hour: 6, minute: 0, grounded: ["sleepDebt"]),
            context: context(includeLatestSafeWake: false), targetIsCritical: false)
        XCTAssertEqual(outcome, .noProposal)
    }

    func testNoGroundedFactorMeansNoProposal() {
        let outcome = TomorrowProposalGenerator.interpret(
            draft(hour: 6, minute: 0, grounded: []), context: context(), targetIsCritical: false)
        XCTAssertEqual(outcome, .noProposal)
    }

    // MARK: bounded by the deterministic latest-safe-wake

    func testSuggestionLaterThanLatestSafeWakeIsRefused() {
        let outcome = TomorrowProposalGenerator.interpret(
            draft(hour: 7, minute: 0, grounded: ["readiness"]), context: context(),
            targetIsCritical: false)
        XCTAssertEqual(outcome, .noProposal, "07:00 is later than latestSafeWake 06:45")
    }

    func testSuggestionAtExactlyLatestSafeWakeIsAllowed() {
        let outcome = TomorrowProposalGenerator.interpret(
            draft(hour: 6, minute: 45, grounded: ["readiness"]), context: context(),
            targetIsCritical: false)
        guard case .proposal = outcome else { return XCTFail("06:45 == latest is allowed") }
    }

    // MARK: out-of-bounds time is refused

    func testOutOfRangeSuggestedTimeIsRefused() {
        let outcome = TomorrowProposalGenerator.interpret(
            draft(hour: 25, minute: 0, grounded: ["readiness"]), context: context(),
            targetIsCritical: false)
        XCTAssertEqual(outcome, .noProposal)
    }

    // MARK: critical schedule changes require confirmation (#6)

    func testCriticalTargetRequiresConfirmation() {
        let outcome = TomorrowProposalGenerator.interpret(
            draft(hour: 6, minute: 0, grounded: ["readiness"]), context: context(),
            targetIsCritical: true)
        guard case .proposal(let proposal) = outcome else { return XCTFail("expected proposal") }
        XCTAssertTrue(proposal.requiresConfirmation)
    }

    // MARK: output is a proposal, not a command

    func testProposalHasNoCommandOrCriticalityField() throws {
        let proposal = TomorrowProposal(
            suggestedWake: try TimeOfDay(hour: 6, minute: 0),
            groundedFactors: [.readiness], rationale: "r", requiresConfirmation: false)
        let fields = Set(Mirror(reflecting: proposal).children.compactMap(\.label))
        XCTAssertEqual(
            fields, ["suggestedWake", "groundedFactors", "rationale", "requiresConfirmation"])
        for forbidden in ["command", "criticality", "proposedCommand"] {
            XCTAssertFalse(fields.contains(forbidden))
        }
    }

    // MARK: model integration + failure fallback

    func testProposeDecodesAValidModelProposal() async {
        let json = #"""
            {"suggestedWakeHour":6,"suggestedWakeMinute":30,"groundedFactorIDs":["readiness"],"rationale":"Rested."}
            """#
        let generator = TomorrowProposalGenerator(
            generator: StructuredGenerator(provider: ScriptedLanguageModelProvider.returning(json)))
        let outcome = await generator.propose(from: context(), targetIsCritical: false)
        guard case .proposal(let proposal) = outcome else { return XCTFail("expected proposal") }
        XCTAssertEqual(proposal.groundedFactors, [.readiness])
    }

    func testProposeReturnsNoProposalWhenModelUnavailable() async {
        let generator = TomorrowProposalGenerator(
            generator: StructuredGenerator(
                provider: ScriptedLanguageModelProvider.failing(.refused)))
        let outcome = await generator.propose(from: context(), targetIsCritical: false)
        XCTAssertEqual(outcome, .noProposal)
    }
}
