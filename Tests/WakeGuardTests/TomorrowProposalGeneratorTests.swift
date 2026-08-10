import Foundation
import XCTest

@testable import WakeGuard

/// WG-168: Tomorrow Agent proposal generation. Verifies the output is a **bounded proposal, not a command**
/// (no command/criticality field, no authority), that **reasons reference actual factors** (fabricated or
/// not-in-context citations are dropped, and a proposal with none is refused), and that a **critical**
/// target flags `requiresConfirmation`. Pins the deterministic safety envelope — never suggest waking later
/// than the latest safe wake, and (WG-168 review fix) never later than a conservative cap when there is no
/// calendar-derived bound at all.
final class TomorrowProposalGeneratorTests: XCTestCase {

    private func maxWake() throws -> TimeOfDay { try TimeOfDay(hour: 10, minute: 0) }

    private func interpret(
        _ draft: AITomorrowPlanProposal, _ context: TomorrowContext, critical: Bool = false
    ) throws -> TomorrowProposalOutcome {
        TomorrowProposalGenerator.interpret(
            draft, context: context, targetIsCritical: critical, maxWake: try maxWake())
    }

    private func context(latestSafeWake: String? = "06:45") -> TomorrowContext {
        var factors = [TomorrowFactor(id: .readiness, value: "good")]
        if let latestSafeWake {
            factors.append(TomorrowFactor(id: .latestSafeWake, value: latestSafeWake))
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
        let outcome = try interpret(draft(hour: 6, minute: 30, grounded: ["readiness"]), context())
        guard case .proposal(let proposal) = outcome else { return XCTFail("expected proposal") }
        XCTAssertEqual(proposal.suggestedWake, try TimeOfDay(hour: 6, minute: 30))
        XCTAssertEqual(proposal.groundedFactors, [.readiness])
        XCTAssertFalse(proposal.requiresConfirmation)
    }

    func testFabricatedCitationsAreDropped() throws {
        let outcome = try interpret(
            draft(hour: 6, minute: 0, grounded: ["readiness", "totallyMadeUp", "readiness"]),
            context())
        guard case .proposal(let proposal) = outcome else { return XCTFail("expected proposal") }
        XCTAssertEqual(
            proposal.groundedFactors, [.readiness], "unknown + duplicate citations removed")
    }

    func testCitationOfAFactorNotInContextIsRefused() throws {
        // `sleepDebt` is a real factor ID but absent from this context — a proposal citing only it has no
        // actual grounding, so it is refused.
        let outcome = try interpret(
            draft(hour: 6, minute: 0, grounded: ["sleepDebt"]), context(latestSafeWake: nil))
        XCTAssertEqual(outcome, .noProposal)
    }

    func testNoGroundedFactorMeansNoProposal() throws {
        XCTAssertEqual(try interpret(draft(hour: 6, grounded: []), context()), .noProposal)
    }

    // MARK: bounded by the deterministic latest-safe-wake

    func testSuggestionLaterThanLatestSafeWakeIsRefused() throws {
        let outcome = try interpret(draft(hour: 7, minute: 0, grounded: ["readiness"]), context())
        XCTAssertEqual(outcome, .noProposal, "07:00 is later than latestSafeWake 06:45")
    }

    func testSuggestionAtExactlyLatestSafeWakeIsAllowed() throws {
        let outcome = try interpret(draft(hour: 6, minute: 45, grounded: ["readiness"]), context())
        guard case .proposal = outcome else { return XCTFail("06:45 == latest is allowed") }
    }

    // MARK: envelope never falls open (WG-168 review) — a bound is always applied

    func testLateSuggestionWithoutLatestSafeWakeIsRefusedByTheCap() throws {
        // Calendar not granted / empty day ⇒ no latestSafeWake factor. A grounded late suggestion must
        // still be bounded by the conservative cap, not surfaced unbounded.
        let outcome = try interpret(
            draft(hour: 23, minute: 59, grounded: ["readiness"]), context(latestSafeWake: nil))
        XCTAssertEqual(outcome, .noProposal, "no calendar bound ⇒ the cap (10:00) applies")
    }

    func testSuggestionWithinCapWithoutLatestSafeWakeIsAllowed() throws {
        let outcome = try interpret(
            draft(hour: 9, minute: 0, grounded: ["readiness"]), context(latestSafeWake: nil))
        guard case .proposal = outcome else { return XCTFail("09:00 is within the 10:00 cap") }
    }

    func testUnparseableLatestSafeWakeFailsClosedToTheCap() throws {
        // A corrupt latestSafeWake value must not disable the bound — it falls closed to the cap.
        let outcome = try interpret(
            draft(hour: 23, minute: 0, grounded: ["readiness"]),
            context(latestSafeWake: "not-a-time"))
        XCTAssertEqual(outcome, .noProposal)
    }

    // MARK: out-of-bounds time is refused

    func testOutOfRangeSuggestedTimeIsRefused() throws {
        XCTAssertEqual(
            try interpret(draft(hour: 25, grounded: ["readiness"]), context()), .noProposal)
    }

    // MARK: critical schedule changes require confirmation (#6)

    func testCriticalTargetRequiresConfirmation() throws {
        let outcome = try interpret(
            draft(hour: 6, minute: 0, grounded: ["readiness"]), context(), critical: true)
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

    func testProposeDecodesAValidModelProposal() async throws {
        let json = #"""
            {"suggestedWakeHour":6,"suggestedWakeMinute":30,"groundedFactorIDs":["readiness"],"rationale":"Rested."}
            """#
        let generator = TomorrowProposalGenerator(
            generator: StructuredGenerator(provider: ScriptedLanguageModelProvider.returning(json)))
        let outcome = await generator.propose(
            from: context(), targetIsCritical: false, maxWake: try maxWake())
        guard case .proposal(let proposal) = outcome else { return XCTFail("expected proposal") }
        XCTAssertEqual(proposal.groundedFactors, [.readiness])
    }

    func testProposeReturnsNoProposalWhenModelUnavailable() async throws {
        let generator = TomorrowProposalGenerator(
            generator: StructuredGenerator(
                provider: ScriptedLanguageModelProvider.failing(.refused)))
        let outcome = await generator.propose(
            from: context(), targetIsCritical: false, maxWake: try maxWake())
        XCTAssertEqual(outcome, .noProposal)
    }
}
