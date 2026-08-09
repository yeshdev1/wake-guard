import XCTest

@testable import WakeGuard

/// WG-090: the coarse, local pre-alarm feedback value. Verifies the user can express "I wasn't awake"
/// vs "helpful" as a two-value category; that the aggregate tally increments coarsely and saturates
/// (never traps, never goes negative); that the category is fail-closed on decode (#27); that the
/// counts serialize with **only coarse count keys** and no identifying / sensitive field (#41); and —
/// the safety line — that the feedback types reference **no** alarm-authority type, so feedback holds
/// no path to whether/when a critical alarm rings or its safety gates (#8/#31).
final class PreAlarmFeedbackTests: XCTestCase {

    func testUserCanExpressBothCoarseCategories() {
        // The two — and only two — coarse categories the user can indicate.
        XCTAssertEqual(
            Set(PreAlarmFeedbackCategory.allCases), [.notAwake, .helpful],
            "feedback is a coarse two-value category — 'I wasn't awake' or 'helpful'")
    }

    func testRecordingIncrementsOnlyTheChosenCategory() {
        let afterNotAwake = PreAlarmFeedbackCounts.empty.recording(.notAwake)
        XCTAssertEqual(afterNotAwake, PreAlarmFeedbackCounts(notAwakeCount: 1, helpfulCount: 0))

        let afterHelpful = afterNotAwake.recording(.helpful)
        XCTAssertEqual(afterHelpful, PreAlarmFeedbackCounts(notAwakeCount: 1, helpfulCount: 1))

        let afterSecondNotAwake = afterHelpful.recording(.notAwake)
        XCTAssertEqual(
            afterSecondNotAwake, PreAlarmFeedbackCounts(notAwakeCount: 2, helpfulCount: 1))
    }

    func testCountsClampNegativesAtZero() {
        // A count is a non-negative frequency by construction — a hand-built negative clamps to zero.
        let counts = PreAlarmFeedbackCounts(notAwakeCount: -5, helpfulCount: -1)
        XCTAssertEqual(counts, .empty)
    }

    func testRecordingSaturatesRatherThanTrapping() {
        // Overflow saturates at Int.max (the WG-080/081 no-trap lesson) rather than crashing.
        let atMax = PreAlarmFeedbackCounts(notAwakeCount: Int.max, helpfulCount: 0)
        XCTAssertEqual(atMax.recording(.notAwake).notAwakeCount, Int.max)
    }

    func testCategoryDecodeIsFailClosed() {
        // An unknown persisted category value must fail to decode (#27), never map to a default.
        let unknown = Data(#""dozing""#.utf8)
        XCTAssertThrowsError(
            try JSONDecoder().decode(PreAlarmFeedbackCategory.self, from: unknown))
    }

    func testCountsRoundTripAndDecodeReClampsNegatives() throws {
        let counts = PreAlarmFeedbackCounts(notAwakeCount: 3, helpfulCount: 7)
        let data = try JSONEncoder().encode(counts)
        XCTAssertEqual(try JSONDecoder().decode(PreAlarmFeedbackCounts.self, from: data), counts)

        // No Codable path can smuggle in a negative count — decode re-runs the clamping init.
        let negative = Data(#"{"notAwakeCount":-4,"helpfulCount":2}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(PreAlarmFeedbackCounts.self, from: negative),
            PreAlarmFeedbackCounts(notAwakeCount: 0, helpfulCount: 2))
    }

    func testCountsStoreOnlyCoarseNonSensitiveKeys() throws {
        // Serialize the tally and assert it carries ONLY the two coarse counts — no timestamp, alarm
        // id, occurrence, or any identifying / sensitive field (#41/#43). Structural + recursive, so a
        // future nested field can't smuggle one in (mirrors the WG-075 CalibrationProfile pattern).
        let counts = PreAlarmFeedbackCounts(notAwakeCount: 2, helpfulCount: 5)
        let data = try JSONEncoder().encode(counts)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys), ["notAwakeCount", "helpfulCount"],
            "the tally stores only coarse counts — no timestamp / id / sensitive field")
        let forbidden = [
            "time", "date", "timestamp", "alarm", "occurrence", "fire", "id", "identifier", "step",
            "motion", "location", "latitude", "longitude", "health", "sleep", "score", "evidence",
            "criticality", "critical", "user", "name",
        ]
        for key in Self.allKeys(object) {
            let lower = key.lowercased()
            XCTAssertFalse(
                forbidden.contains { lower.contains($0) }, "unexpected sensitive key: \(key)")
        }
    }

    private static func allKeys(_ value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            return Array(dictionary.keys) + dictionary.values.flatMap(allKeys)
        }
        if let array = value as? [Any] {
            return array.flatMap(allKeys)
        }
        return []
    }

    func testFeedbackTypesReferenceNoAlarmAuthority() {
        // STRUCTURAL proof of "cannot silently retune critical behavior": reflect over the feedback
        // value's stored properties and confirm none is an alarm-authority / scheduling / criticality
        // type. The tally is pure counts, so it has no field through which it could reach an alarm.
        let mirror = Mirror(reflecting: PreAlarmFeedbackCounts(notAwakeCount: 1, helpfulCount: 1))
        for child in mirror.children {
            let typeName = String(describing: type(of: child.value))
            let forbidden = [
                "Alarm", "AlarmID", "AlarmCommand", "Criticality", "ScheduleRule", "AwakeEvidence",
                "Config",
            ]
            XCTAssertFalse(
                forbidden.contains { typeName.contains($0) },
                "feedback must hold no alarm-authority field; found \(typeName)")
        }
        // And the whole value is two Ints — recording feedback is a pure count transform with no alarm.
        XCTAssertEqual(mirror.children.count, 2)
    }
}
