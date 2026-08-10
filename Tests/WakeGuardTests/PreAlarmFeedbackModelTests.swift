import XCTest

@testable import WakeGuard

/// Runs-on-a-phone step 7: the pre-alarm feedback affordance model (WG-090). Verifies a tap records the
/// chosen coarse category to the store and marks the session recorded (so the view thanks the user and
/// stops offering) — advisory only; recording never touches an alarm (that safety property is pinned by
/// the WG-090 store tests).
@MainActor
final class PreAlarmFeedbackModelTests: XCTestCase {

    func testRecordingWritesTheChosenCategoryAndMarksRecorded() async {
        let store = InMemoryPreAlarmFeedbackStore()
        let model = PreAlarmFeedbackModel(store: store)
        XCTAssertNil(model.recorded, "nothing is recorded until the user taps")

        await model.record(.notAwake)

        XCTAssertEqual(
            model.recorded, .notAwake, "the session is marked so the view stops offering")
        let counts = await store.counts()
        XCTAssertEqual(counts.notAwakeCount, 1, "only the chosen category is incremented")
        XCTAssertEqual(counts.helpfulCount, 0)
    }

    func testRecordingHelpfulIncrementsOnlyHelpful() async {
        let store = InMemoryPreAlarmFeedbackStore()
        let model = PreAlarmFeedbackModel(store: store)
        await model.record(.helpful)
        XCTAssertEqual(model.recorded, .helpful)
        let counts = await store.counts()
        XCTAssertEqual(counts.helpfulCount, 1)
        XCTAssertEqual(counts.notAwakeCount, 0)
    }
}
