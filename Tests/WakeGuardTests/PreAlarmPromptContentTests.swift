import XCTest

@testable import WakeGuard

/// WG-083: the pre-alarm prompt content. Verifies the buttons include **keep** (always) plus **off
/// today / change time / remind later as configured**, that the **warning states the original alarm
/// remains unless amended** (#7), that every string is a **localization-ready** key, and that a
/// critical alarm's destructive action is flagged for confirmation (#6). The content is a pure model
/// with no alarm authority — building it changes nothing (#8).
final class PreAlarmPromptContentTests: XCTestCase {

    private func promptRecommendation(
        offered: Set<PreAlarmAction>, criticality: Criticality = .standard
    ) throws -> PreAlarmRecommendation {
        let policy = try PreAlarmPolicy.enabled(leadTime: 600, allowedActions: offered)
        let evidence = AwakeEvidenceModel.evaluate(
            AwakeEvidenceInput(
                recentStepCount: 30, longestEpisodeDuration: 0, secondsSinceLastMovement: 60,
                deviceInteracted: false))
        return PreAlarmEvaluator.evaluate(
            policy: policy, criticality: criticality, timeRemaining: 300, evidence: evidence)
    }

    private func content(
        offered: Set<PreAlarmAction>, criticality: Criticality = .standard
    ) throws -> PreAlarmPromptContent {
        try XCTUnwrap(
            PreAlarmPromptContent.from(
                promptRecommendation(offered: offered, criticality: criticality)))
    }

    // MARK: - Actions as configured (keep always present)

    func testKeepIsAlwaysFirstEvenWithMinimalConfig() throws {
        let buttons = try content(offered: [.turnOffToday]).buttons
        XCTAssertEqual(
            buttons.first?.action, .keep, "keep is always the first, safe-default button")
        XCTAssertEqual(buttons.map(\.action), [.keep, .turnOffToday])
    }

    func testAllConfiguredActionsAppearInSafeToDestructiveOrder() throws {
        let buttons = try content(offered: [.turnOffToday, .changeTime, .remindLater]).buttons
        XCTAssertEqual(
            buttons.map(\.action), [.keep, .remindLater, .changeTime, .turnOffToday],
            "keep first, then least → most destructive")
    }

    func testOnlyConfiguredActionsAppear() throws {
        let actions = try content(offered: [.remindLater]).buttons.map(\.action)
        XCTAssertEqual(actions, [.keep, .remindLater])
        XCTAssertFalse(actions.contains(.turnOffToday))
        XCTAssertFalse(actions.contains(.changeTime))
    }

    func testInformationalPromptHasOnlyKeep() throws {
        XCTAssertEqual(try content(offered: []).buttons.map(\.action), [.keep])
    }

    func testNoContentWhenNotPrompting() {
        let evidence = AwakeEvidenceModel.evaluate(
            AwakeEvidenceInput(
                recentStepCount: 30, longestEpisodeDuration: 0, secondsSinceLastMovement: 60,
                deviceInteracted: false))
        let decline = PreAlarmEvaluator.evaluate(
            policy: .disabled, criticality: .standard, timeRemaining: 300, evidence: evidence)
        XCTAssertNil(PreAlarmPromptContent.from(decline), "no prompt → no content")
    }

    // MARK: - Warning (#7)

    func testWarningStatesOriginalAlarmRemains() throws {
        let warning = PreAlarmPromptStrings.developmentFallback(
            for: try content(offered: [.turnOffToday]).warningKey)
        XCTAssertTrue(warning.contains("stays scheduled"), "the #7 guarantee is stated: \(warning)")
        XCTAssertTrue(
            warning.lowercased().contains("unless"), "conditioned on the user amending it")
    }

    func testInformationalPromptStillCarriesTheWarning() throws {
        // The keep-only prompt is the honesty-critical case: no destructive buttons, but the #7
        // guarantee must still be shown so the user can't mistake it for "already off".
        let warning = PreAlarmPromptStrings.developmentFallback(
            for: try content(offered: []).warningKey)
        XCTAssertTrue(warning.contains("stays scheduled"), warning)
    }

    // MARK: - Destructive + confirmation flags (#6)

    func testDestructiveFlagsAreCorrect() throws {
        let byAction = Dictionary(
            uniqueKeysWithValues: try content(offered: [.turnOffToday, .changeTime, .remindLater])
                .buttons.map { ($0.action, $0) })
        XCTAssertEqual(byAction[.turnOffToday]?.isDestructive, true)
        XCTAssertEqual(byAction[.changeTime]?.isDestructive, true)
        XCTAssertEqual(byAction[.remindLater]?.isDestructive, false)
        XCTAssertEqual(byAction[.keep]?.isDestructive, false)
    }

    func testCriticalConfirmsDestructiveActionsOnly() throws {
        let byAction = Dictionary(
            uniqueKeysWithValues: try content(
                offered: [.turnOffToday, .remindLater], criticality: .critical
            ).buttons.map { ($0.action, $0) })
        XCTAssertEqual(byAction[.turnOffToday]?.requiresConfirmation, true, "#6 on the turn-off")
        XCTAssertEqual(byAction[.remindLater]?.requiresConfirmation, false, "nothing to confirm")
        XCTAssertEqual(byAction[.keep]?.requiresConfirmation, false)
    }

    func testStandardNeverConfirms() throws {
        let buttons = try content(offered: [.turnOffToday, .changeTime]).buttons
        XCTAssertTrue(
            buttons.allSatisfy { !$0.requiresConfirmation }, "standard alarm — no confirm")
    }

    func testOnlyChangeTimeOpensApp() throws {
        let byAction = Dictionary(
            uniqueKeysWithValues: try content(offered: [.turnOffToday, .changeTime, .remindLater])
                .buttons.map { ($0.action, $0) })
        XCTAssertEqual(byAction[.changeTime]?.opensApp, true, "changing the time needs a picker")
        XCTAssertEqual(byAction[.turnOffToday]?.opensApp, false)
        XCTAssertEqual(byAction[.remindLater]?.opensApp, false)
        XCTAssertEqual(byAction[.keep]?.opensApp, false)
    }

    // MARK: - Localization-ready + stable identifiers

    func testEveryDisplayedStringIsAResolvableLocalizationKey() throws {
        let content = try content(offered: [.turnOffToday, .changeTime, .remindLater])
        for key in [content.titleKey, content.warningKey] + content.buttons.map(\.titleKey) {
            XCTAssertNotEqual(
                PreAlarmPromptStrings.developmentFallback(for: key), key,
                "\(key) must resolve to real copy, not fall back to the key")
        }
    }

    func testActionIdentifiersAreStable() {
        XCTAssertEqual(PreAlarmPromptAction.keep.identifier, "prealarm.action.keep")
        XCTAssertEqual(PreAlarmPromptAction.turnOffToday.identifier, "prealarm.action.turnOffToday")
        XCTAssertEqual(PreAlarmPromptAction.changeTime.identifier, "prealarm.action.changeTime")
        XCTAssertEqual(PreAlarmPromptAction.remindLater.identifier, "prealarm.action.remindLater")
        XCTAssertEqual(PreAlarmPromptContent.categoryIdentifier, "prealarm.prompt")
    }
}
