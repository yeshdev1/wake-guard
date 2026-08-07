import XCTest

/// WG-050: UI tests for the core alarm flows, driven entirely through the app's accessibility
/// identifiers. The app launches with `-uiTesting`, which composes an **isolated, empty
/// in-memory** store, so each test starts from a known-empty list and never touches the user's
/// real alarms. Screenshots of key states are attached for the release baseline.
@MainActor
final class CoreAlarmFlowsUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        return app
    }

    /// Create an alarm from the empty list: open the form, optionally name it, optionally mark it
    /// critical, and save. Leaves the app back on the list. When `critical` is set, the label is
    /// left blank so no keyboard covers the toggle.
    private func createAlarm(_ app: XCUIApplication, label: String = "", critical: Bool = false) {
        XCTAssertTrue(app.buttons["addAlarmButton"].waitForExistence(timeout: 10))
        app.buttons["addAlarmButton"].tap()

        let field = app.textFields["alarmLabelField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the create form opened")
        if !label.isEmpty {
            field.tap()
            field.typeText(label)
        }
        if critical {
            setCriticalOn(app)
        }
        app.buttons["saveAlarmButton"].tap()
    }

    /// Turn the critical toggle on, robustly: a plain `.tap()` on a SwiftUI switch doesn't always
    /// flip it, so verify and fall back to tapping the control edge.
    private func setCriticalOn(_ app: XCUIApplication) {
        let toggle = app.switches["criticalAlarmToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        if (toggle.value as? String) != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "1", "the critical toggle is on")
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Flows

    func testAppLaunchesToTheAlarmList() {
        let app = launch()
        XCTAssertTrue(
            app.navigationBars["Alarms"].waitForExistence(timeout: 15),
            "the app launches to the alarm list")
        XCTAssertTrue(app.buttons["addAlarmButton"].waitForExistence(timeout: 5))
        snapshot(app, "01-empty-list")
    }

    func testCreateAlarmAppearsInList() {
        let app = launch()
        app.buttons["addAlarmButton"].tap()
        XCTAssertTrue(app.textFields["alarmLabelField"].waitForExistence(timeout: 5))
        snapshot(app, "02-create-form")

        app.textFields["alarmLabelField"].tap()
        app.textFields["alarmLabelField"].typeText("Morning")
        app.buttons["saveAlarmButton"].tap()

        XCTAssertTrue(
            app.staticTexts["Morning"].waitForExistence(timeout: 10),
            "the new alarm appears in the list")
        snapshot(app, "03-list-with-alarm")
    }

    func testEditAlarmPersistsAChange() {
        let app = launch()
        createAlarm(app, label: "Morning")
        XCTAssertTrue(app.staticTexts["Morning"].waitForExistence(timeout: 10))

        // Open the alarm for editing and turn it critical.
        firstAlarmRow(app).tap()
        XCTAssertTrue(
            app.navigationBars["Edit Alarm"].waitForExistence(timeout: 5), "the edit form opened")
        setCriticalOn(app)
        app.buttons["saveAlarmButton"].tap()

        // Re-open it: the change round-tripped through persistence.
        XCTAssertTrue(app.staticTexts["Morning"].waitForExistence(timeout: 10))
        firstAlarmRow(app).tap()
        let reopened = app.switches["criticalAlarmToggle"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        XCTAssertEqual(reopened.value as? String, "1", "the critical change persisted")
    }

    func testDeleteAlarmRemovesIt() {
        let app = launch()
        createAlarm(app, label: "Temporary")
        XCTAssertTrue(app.staticTexts["Temporary"].waitForExistence(timeout: 10))

        firstAlarmRow(app).swipeLeft()
        let delete = app.buttons["deleteAlarm"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        // A standard alarm deletes without confirmation.
        XCTAssertTrue(
            waitForDisappearance(of: app.staticTexts["Temporary"], timeout: 10),
            "the alarm is removed from the list")
    }

    func testCriticalAlarmConfirmsOnDelete() {
        let app = launch()
        createAlarm(app, critical: true)  // blank label → no keyboard over the toggle
        XCTAssertTrue(firstAlarmRow(app).waitForExistence(timeout: 10))
        snapshot(app, "04-critical-alarm")

        firstAlarmRow(app).swipeLeft()
        app.buttons["deleteAlarm"].tap()

        // Deleting a critical alarm requires explicit confirmation (#6): the alert appears, and
        // cancelling leaves the alarm in place.
        let confirm = app.alerts["Confirm change"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "a critical delete asks to confirm")
        snapshot(app, "05-critical-confirm")
        confirm.buttons["Cancel"].tap()
        XCTAssertTrue(
            firstAlarmRow(app).waitForExistence(timeout: 5),
            "cancelling leaves the critical alarm unchanged")
    }

    func testTravelOptionIsSelectable() {
        let app = launch()
        app.buttons["addAlarmButton"].tap()
        XCTAssertTrue(app.textFields["alarmLabelField"].waitForExistence(timeout: 5))
        app.textFields["alarmLabelField"].tap()
        app.textFields["alarmLabelField"].typeText("Trip")

        let picker = app.buttons["travelBehaviorPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let option = app.buttons["Keep home-zone time"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "the travel options are shown")
        snapshot(app, "06-travel-options")
        option.tap()

        app.buttons["saveAlarmButton"].tap()
        XCTAssertTrue(
            app.staticTexts["Trip"].waitForExistence(timeout: 10),
            "the alarm saves with the chosen travel behavior")
    }

    // MARK: - Helpers

    /// The first alarm row's tappable element. The row combines its children into one
    /// accessibility element (`.ignore` + a custom label), which SwiftUI can expose as a generic
    /// element rather than a `button`, so match the `alarmRow` identifier on any element type.
    private func firstAlarmRow(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "alarmRow").firstMatch
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}
