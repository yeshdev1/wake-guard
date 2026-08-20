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

    /// Readiness itself is degraded here — the simulator has no HealthKit sleep data — but the **movement**
    /// section is the graph's `FixtureMotionActivityHistory` night, so this is the only place the section's
    /// success rendering is exercised end-to-end (WG-318). Asserting it *before* the snap is deliberate: the
    /// reference screenshot previously captured "This device can't track movement" and nothing checked what
    /// was in it, so a false claim sat in a committed artefact across four rounds of review. A screenshot no
    /// assertion guards is a picture of whatever happened.
    func testTour4ReadinessDegraded() {
        let app = launch()
        tap(app, "readinessButton")

        // **The positive control for tour 7.** These two identifiers are the ones
        // `testTour7ReadinessSleepReadFailed` asserts are *absent*, and until this round nothing anywhere
        // observed either of them present: the `readinessMissing` wait below discarded its own result, and
        // `readinessSummary` was referenced by no test at any layer. A negative assertion against a selector
        // never once seen to match is satisfied by a rename, a merged accessibility element, or a screen that
        // failed to load — it would pass forever while asserting nothing. Asserting them here is what makes
        // tour 7's `XCTAssertFalse`s evidence rather than decoration.
        XCTAssertTrue(
            find(app, "readinessMissing").waitForExistence(timeout: 12),
            """
            the .assessed branch is not naming its missing factors, so tour 7's assertion that the \
            .unavailable branch omits them is vacuous
            """)
        XCTAssertTrue(
            find(app, "readinessSummary").exists,
            """
            the .assessed branch is not rendering its readiness summary, so tour 7's assertion that the \
            .unavailable branch makes no such claim is vacuous
            """)

        XCTAssertTrue(
            find(app, "readinessRestEstimate").waitForExistence(timeout: 12),
            "the movement section shows no rest estimate, so the screenshot documents an empty section"
        )
        XCTAssertTrue(
            find(app, "readinessDisturbances").exists,
            "the movement section shows no disturbance line")
        XCTAssertFalse(
            find(app, "readinessMovementUnavailable").exists,
            """
            the movement section is reporting a reason it has no estimate; the reference screenshot would \
            record that claim as the product's appearance
            """)
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

    /// The readiness card's **`.unavailable`** branch — a sleep read that failed (WG-322). Reached only via
    /// `-uiTestingSleepReadFails`; the default graph's `UnavailableSleepQuery` returns `[]`, a *concluded*
    /// read, which is why `testTour4ReadinessDegraded` above lands in `.assessed` instead.
    ///
    /// This is the branch the **M4** mutant reached in WG-319 round fourteen — rewriting
    /// `ReadinessDisplayState.cardContent`'s `.unavailable` arm to `return nil` left all 1435 tests green
    /// while restoring the permanent spinner, the hidden card and the hidden movement section.
    ///
    /// **M4 itself is no longer the gap:** round fourteen closed it at the unit layer, and
    /// `ReadinessDisplayStateTests.testOnlyLoadingWithholdsTheCardSoAConcludedReadAlwaysRendersOne` now
    /// asserts `cardContent == .unavailable(reason)` for every case, inside `ci-fast`. What that test cannot
    /// reach is the seam one layer further out: the `if let content = model.readiness.cardContent` at
    /// `ReadinessScreen.swift:51` that *consumes* the property. Re-gating that `if let` on `assessment != nil`
    /// — WG-319's original defect verbatim — survives all 1448 unit tests and is killed only here. That is
    /// what this case is for; describing it as "closing M4" names the right line for the wrong reason.
    ///
    /// So the first assertion is **positive** — it fails if the card is not on screen — and the rest state
    /// what this branch is forbidden from doing.
    func testTour7ReadinessSleepReadFailed() {
        let app = launch(sleepReadFails: true)
        tap(app, "readinessButton")

        XCTAssertTrue(
            find(app, "readinessUnavailableReason").waitForExistence(timeout: 20),
            """
            the card is not showing why the sleep read produced nothing; if the spinner is still up this is \
            WG-319's defect restored (the M4 mutant), and the whole card — including the always-on movement \
            section — is hidden with it
            """)
        XCTAssertFalse(
            find(app, "readinessLoading").exists,
            "the screen is still showing 'Checking your sleep readiness…' with no query in flight")

        // The *sentence*, not just the identifier. `unavailableSection` binds `Label(reason.message, …)` to
        // the enum, and nothing observed that binding: `ReadinessDisplayStateTests` pins
        // `ReadinessUnavailability.message` (the enum), while the assertion above pins only that some element
        // carries this identifier. So `Label("There isn't enough sleep data yet.", …)` — the exact false
        // claim WG-319 exists to remove — survived the whole suite, unit and UI. The prohibition list is
        // `testNoMessageMakesAClaimAboutHowMuchSleepDataTheUserHas`'s, applied one layer out to what the
        // reader actually sees.
        let reasonLabel = find(app, "readinessUnavailableReason").label.lowercased()
        XCTAssertTrue(
            reasonLabel.contains("couldn't check your sleep readiness"),
            """
            the card's unavailability line is not the sentence bound to ReadinessUnavailability.message; \
            it reads "\(reasonLabel)"
            """)
        for claim in ["enough", "sleep data", "add a few nights", "more data", "no data"] {
            XCTAssertFalse(
                reasonLabel.contains(claim),
                """
                the card says "\(claim)" on a read that returned nothing — a statement about the user's \
                sleep data made from data the query never looked at: "\(reasonLabel)"
                """)
        }

        // WG-318's guarantee under WG-319's failure branch: a failed *sleep* read must not take the
        // always-on movement section down with it. No check anywhere observes the two together.
        //
        // Asserting the section **resolves**, not merely that its header is present:
        // `readinessMovementHeader` is emitted by all three arms of the movement switch (loading, available,
        // unavailable), and on a cold open the movement read is still in flight when the sleep read has
        // already thrown — so a header check alone cannot tell "survived" from "spinning forever", and a
        // mutant deleting `applyMovementSummary` would survive it. The graph's `FixtureMotionActivityHistory`
        // is unchanged by `-uiTestingSleepReadFails`, so a real night is expected here exactly as in tour 4.
        XCTAssertTrue(
            find(app, "readinessMovementHeader").exists,
            "a failed sleep read has hidden the always-on Movement overnight section")
        XCTAssertTrue(
            find(app, "readinessRestEstimate").waitForExistence(timeout: 20),
            """
            the Movement overnight section is present but never resolved on the failed-sleep-read branch — \
            the section is there and says nothing, which is the defect WG-318 exists to prevent
            """)
        XCTAssertFalse(
            find(app, "readinessMovementUnavailable").exists,
            """
            a failed *sleep* read has been reported as a failed *movement* read; the two are independent and \
            this card renders both at once
            """)

        // Round twelve's defect, pinned end to end for the first time: nothing was read, so the card must
        // make no claim about how much sleep data the reader has.
        XCTAssertFalse(
            find(app, "readinessSummary").exists,
            "the card is explaining a readiness assessment it never computed")
        XCTAssertFalse(
            find(app, "readinessMissing").exists,
            """
            the card is naming factors as absent from data the query never looked at — the "There isn't \
            enough sleep data yet" claim WG-319 removed from this branch
            """)

        // Round eighteen moved the disclaimer outside both switches precisely so it holds on this branch,
        // where the card contains no estimate to disclaim. It localizes only by being a literal in `Text`,
        // so no unit test can reach it (recorded in SMK-17); this branch renders it, so the check is free.
        XCTAssertTrue(
            find(app, "readinessDisclaimer").exists,
            "the not-a-diagnosis note is absent on the .unavailable branch (#39, PRODUCT_SPEC.md:65)"
        )

        snap(app, "19-readiness-sleep-read-failed")
    }

    // MARK: - Helpers

    /// `sleepReadFails` composes a throwing sleep query (WG-322). Defaulted, so every tour above launches the
    /// unchanged graph — a graph that could only fail would delete the success coverage tour 4 documents.
    private func launch(sleepReadFails: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            sleepReadFails
            ? ["-uiTesting", "-uiTestingSleepReadFails"] : ["-uiTesting"]
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
