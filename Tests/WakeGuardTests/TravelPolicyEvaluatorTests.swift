import XCTest

@testable import WakeGuard

/// WG-104: the travel policy evaluator. Verifies each `TravelBehavior` yields a **deterministic**
/// decision, that **location can never silently override the system zone** (the outcome is identical
/// whether or not a location change corroborates — certainty only words the explanation), that the
/// evidence/explanation is **explainable** from recorded factors (#32), and — the safety pin — that a
/// decision holds **no alarm authority** and an `askOnChange` prompt always keeps a safe standing default
/// (#7/#16).
final class TravelPolicyEvaluatorTests: XCTestCase {

    private let evaluator = TravelPolicyEvaluator()

    private func iana(_ identifier: String) throws -> IANATimeZone {
        try IANATimeZone(identifier: identifier)
    }

    /// A Tokyo → New York move carrying the given (optional) coarse location corroboration.
    private func travelContext(location: LocationContext?) throws -> TravelContext {
        TravelContext(
            zoneChange: TimeZoneChange(
                previous: try iana("Asia/Tokyo"), current: try iana("America/New_York")),
            detectedAt: Date(timeIntervalSince1970: 1_000_000),
            location: location)
    }

    /// A Tokyo → New York move, with or without a corroborating location change.
    private func context(corroborated: Bool) throws -> TravelContext {
        try travelContext(
            location: corroborated
                ? LocationContext(
                    significantLocationChanged: true,
                    observedAt: Date(timeIntervalSince1970: 1_000_000))
                : nil)
    }

    private func anchor() throws -> IANATimeZone { try iana("Asia/Tokyo") }

    // MARK: - Deterministic per-behavior outcomes

    func testFollowLocalResolvesToDeviceZoneWithoutPrompting() throws {
        let decision = evaluator.evaluate(
            travel: try context(corroborated: true), behavior: .followLocal,
            anchorZone: try anchor())
        XCTAssertEqual(decision.outcome, .resolved(.followDeviceZone))
    }

    func testStayFixedResolvesToAnchorZoneWithoutPrompting() throws {
        let decision = evaluator.evaluate(
            travel: try context(corroborated: true), behavior: .stayFixed, anchorZone: try anchor())
        XCTAssertEqual(decision.outcome, .resolved(.keepAnchorZone))
    }

    func testAskOnChangePromptsWithASafeStandingDefault() throws {
        let decision = evaluator.evaluate(
            travel: try context(corroborated: true), behavior: .askOnChange,
            anchorZone: try anchor())
        // The standing (no-response) default is always the safe anchor (#7/#16); follow-local is only
        // offered as the alternative, never applied without an explicit choice.
        XCTAssertEqual(
            decision.outcome, .prompt(standing: .keepAnchorZone, alternative: .followDeviceZone))
    }

    func testRegionRuleResolvesViaItsSafeFallback() throws {
        let follow = TravelBehavior.regionRule(
            RegionRule(regionIdentifier: "home", safeFallback: .followLocal))
        let fixed = TravelBehavior.regionRule(
            RegionRule(regionIdentifier: "home", safeFallback: .stayFixed))
        XCTAssertEqual(
            evaluator.evaluate(
                travel: try context(corroborated: false), behavior: follow, anchorZone: try anchor()
            )
            .outcome, .resolved(.followDeviceZone))
        XCTAssertEqual(
            evaluator.evaluate(
                travel: try context(corroborated: false), behavior: fixed, anchorZone: try anchor()
            )
            .outcome, .resolved(.keepAnchorZone))
    }

    // MARK: - Location cannot silently override the system zone

    func testLocationNeverChangesOutcomeOrEvidence() throws {
        // The outcome AND evidence must be identical across the FULL location domain — absent, present
        // but unmoved, and a genuine move — for every behavior. Location can neither force a re-anchor
        // nor block one; only the system zone + behavior decide (certainty only words the explanation).
        let observedAt = Date(timeIntervalSince1970: 1_000_000)
        let locations: [LocationContext?] = [
            nil,
            LocationContext(significantLocationChanged: false, observedAt: observedAt),
            LocationContext(significantLocationChanged: true, observedAt: observedAt),
        ]
        let behaviors: [TravelBehavior] = [
            .followLocal, .stayFixed, .askOnChange,
            .regionRule(RegionRule(regionIdentifier: "home", safeFallback: .followLocal)),
            .regionRule(RegionRule(regionIdentifier: "home", safeFallback: .stayFixed)),
        ]
        let anchorZone = try anchor()
        for behavior in behaviors {
            let decisions = try locations.map { location in
                evaluator.evaluate(
                    travel: try travelContext(location: location), behavior: behavior,
                    anchorZone: anchorZone)
            }
            for decision in decisions.dropFirst() {
                XCTAssertEqual(
                    decision.outcome, decisions[0].outcome,
                    "location must not change the \(behavior) outcome")
                XCTAssertEqual(
                    decision.evidence, decisions[0].evidence,
                    "location must not change the \(behavior) evidence")
            }
        }
    }

    func testFollowLocalAppliesEvenWhenLocationIsUnavailable() throws {
        // A real trip with location denied (zoneChangeOnly) must still follow local — location absence
        // never blocks the user's chosen behavior.
        let decision = evaluator.evaluate(
            travel: try context(corroborated: false), behavior: .followLocal,
            anchorZone: try anchor())
        XCTAssertEqual(decision.outcome, .resolved(.followDeviceZone))
    }

    // MARK: - Explainability (#32)

    func testExplanationNamesBothZonesAndCorroborationIsCoarse() throws {
        let corroborated = evaluator.evaluate(
            travel: try context(corroborated: true), behavior: .followLocal,
            anchorZone: try anchor())
        XCTAssertTrue(corroborated.explanation.contains("Asia/Tokyo"))
        XCTAssertTrue(corroborated.explanation.contains("America/New_York"))
        XCTAssertTrue(corroborated.explanation.contains("location change corroborates"))

        let uncorroborated = evaluator.evaluate(
            travel: try context(corroborated: false), behavior: .followLocal,
            anchorZone: try anchor())
        XCTAssertTrue(uncorroborated.explanation.contains("no location corroboration"))
    }

    func testEvidenceReferencesRecordedFactorsOnly() throws {
        let decision = evaluator.evaluate(
            travel: try context(corroborated: true), behavior: .stayFixed, anchorZone: try anchor())
        // Exactly the recorded factors — the time-zone change and the user preference; no location kind
        // exists, so a coordinate can never appear (#32/#41).
        XCTAssertEqual(decision.evidence.map(\.kind), [.timeZoneChange, .userPreference])
        XCTAssertEqual(decision.evidence[0].reference, "Asia/Tokyo->America/New_York")
        XCTAssertEqual(decision.evidence[1].reference, "travelBehavior:stayFixed")
    }

    func testEvaluationIsPureAndDeterministic() throws {
        let travel = try context(corroborated: true)
        let first = evaluator.evaluate(
            travel: travel, behavior: .askOnChange, anchorZone: try anchor())
        let second = evaluator.evaluate(
            travel: travel, behavior: .askOnChange, anchorZone: try anchor())
        XCTAssertEqual(first, second)
    }

    // MARK: - No alarm authority (safety pin)

    func testDecisionHoldsNoAlarmAuthority() throws {
        // The decision carries a zone resolution + explanation + evidence — nothing referencing an
        // AlarmCommand, criticality, or mutation. It advises; it can never suppress a critical alarm.
        let decision = evaluator.evaluate(
            travel: try context(corroborated: true), behavior: .askOnChange,
            anchorZone: try anchor())
        let mirror = Mirror(reflecting: decision)
        XCTAssertEqual(
            Set(mirror.children.compactMap(\.label)), ["outcome", "explanation", "evidence"])
    }
}
