import XCTest

/// A guided **screenshot tour** of every reachable screen — a visual QA reference (not an assertion suite).
/// Launches the `-uiTesting` isolated in-memory graph, navigates purely by accessibility identifier, and
/// attaches a labeled screenshot per screen. `continueAfterFailure = true` and every step is guarded, so one
/// flaky tap never blocks the rest of the tour. Extract the PNGs from the `.xcresult` afterwards.
///
/// Note: the `-uiTesting` graph skips onboarding and shows the "won't ring here" banner (the interim deferred
/// adapter) — capture onboarding + the real permission banner from a production simulator launch separately.
@MainActor
final class ScreenshotTourUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    // MARK: - Tours

    func testTour1ListAndCreateForm() {
        let app = launch()
        _ = app.navigationBars["Alarms"].waitForExistence(timeout: 25)
        snap(app, "01-list-empty")

        snap(app, "02-creation-header")

        tap(app, "addManualAlarmButton")
        _ = find(app, "saveAlarmButton").waitForExistence(timeout: 10)
        snap(app, "03-create-form")

        let field = app.textFields["alarmLabelField"]
        if field.waitForExistence(timeout: 4) {
            field.tap()
            field.typeText("Morning")
        }
        tap(app, "saveAlarmButton")
        _ = app.staticTexts["Morning"].waitForExistence(timeout: 10)
        snap(app, "04-list-with-alarm")
    }

    func testTour2CriticalGateAndEdit() {
        let app = launch()
        tap(app, "addManualAlarmButton")
        setCriticalOn(app)
        snap(app, "05-create-critical")
        tap(app, "saveAlarmButton")

        let row = find(app, "alarmRow")
        _ = row.waitForExistence(timeout: 12)
        snap(app, "06-list-critical")

        row.swipeLeft()
        tap(app, "deleteAlarm")
        let confirm = app.alerts["Confirm change"]
        if confirm.waitForExistence(timeout: 6) {
            snap(app, "07-critical-confirm-gate")
            confirm.buttons["Cancel"].tap()
        }
        if row.waitForExistence(timeout: 5) { row.tap() }
        if app.navigationBars["Edit Alarm"].waitForExistence(timeout: 6) {
            snap(app, "08-edit-form")
        }
    }

    func testTour3ConversationalFailClosed() {
        let app = launch()
        tap(app, "describeAlarmButton")
        let input = app.textFields["conversationalAlarmInput"]
        if input.waitForExistence(timeout: 10) {
            snap(app, "09-conversational-input")
            input.tap()
            input.typeText("wake me at 7 tomorrow")
            tap(app, "conversationalAlarmSubmit")
        }
        // No on-device model in the sim → fail closed to the manual editor.
        _ = find(app, "conversationalManualEditor").waitForExistence(timeout: 10)
        snap(app, "10-conversational-failclosed")
    }

    func testTour4ReadinessDegraded() {
        let app = launch()
        tap(app, "readinessButton")
        _ = find(app, "readinessMissing").waitForExistence(timeout: 12)
        snap(app, "11-readiness-degraded")
    }

    func testTour5Privacy() {
        let app = launch()
        tap(app, "privacySettingsButton")
        _ = find(app, "privacyLinkExport").waitForExistence(timeout: 10)
        snap(app, "12-privacy-hub")

        tourInto(app, link: "privacyLinkExport", wait: "dataExportPrepare", name: "13-export")
        tourInto(app, link: "privacyLinkConsent", wait: "consentStatus", name: "14-consent")
        tourInto(
            app, link: "privacyLinkDiagnostics", wait: "diagnosticsExport", name: "15-diagnostics")
        tourInto(
            app, link: "privacyLinkDelete", wait: "dataDeletionRequestFullReset", name: "16-delete")
    }

    func testTour6Challenge() {
        let app = launch()
        tap(app, "addManualAlarmButton")
        // Configure a walk challenge so the row exposes "Test challenge".
        if find(app, "challengeKindPicker").waitForExistence(timeout: 8) {
            find(app, "challengeKindPicker").tap()
            let walk = app.buttons["Walk"]
            if walk.waitForExistence(timeout: 4) { walk.tap() }
        }
        tap(app, "saveAlarmButton")
        let row = find(app, "alarmRow")
        _ = row.waitForExistence(timeout: 12)
        row.swipeRight()
        if find(app, "testChallenge").waitForExistence(timeout: 5) {
            find(app, "testChallenge").tap()
            _ = find(app, "challengeView").waitForExistence(timeout: 8)
            snap(app, "17-walk-challenge")
            if find(app, "challengeAccessibleAlternative").waitForExistence(timeout: 4) {
                find(app, "challengeAccessibleAlternative").tap()
                _ = find(app, "mathPuzzleView").waitForExistence(timeout: 6)
                snap(app, "18-accessible-fallback")
            }
        }
    }

    // MARK: - Helpers

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Match an identifier on **any** element type (a NavigationLink can surface as a non-button element).
    private func find(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func tap(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval = 10) {
        let element = find(app, identifier)
        if element.waitForExistence(timeout: timeout) { element.tap() }
    }

    /// Push into a privacy sub-screen, snapshot it, then pop back to the hub.
    private func tourInto(_ app: XCUIApplication, link: String, wait: String, name: String) {
        tap(app, link)
        _ = find(app, wait).waitForExistence(timeout: 8)
        snap(app, name)
        let back = app.navigationBars.buttons.firstMatch
        if back.waitForExistence(timeout: 4) { back.tap() }
    }

    private func setCriticalOn(_ app: XCUIApplication) {
        let toggle = app.switches["criticalAlarmToggle"]
        guard toggle.waitForExistence(timeout: 8) else { return }
        toggle.tap()
        if (toggle.value as? String) != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
    }
}
