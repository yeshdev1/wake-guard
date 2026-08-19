import XCTest

@testable import WakeGuard

/// WG-310/311/318: the copy for the "Movement overnight" section when it **does** have an estimate.
///
/// Split from the file above only by subject; the rules are deliberately the same ones. That is the point —
/// the unavailable reasons were held to "name no device the reader may not own" through four rounds of
/// review while the success branch, two lines away on the same screen, was reachable from no test at all and
/// kept both an iPhone-only glyph and phone-specific wording.
final class MovementEstimateCopyTests: XCTestCase {

    /// Every line the section can show, unavailable **and** available, in one place — so a rule applied
    /// below is applied to the whole section rather than to whichever half is currently under review.
    private var everySuccessLine: [String] {
        [
            MovementEstimateCopy.disturbanceText(SleepDisturbances(pickups: 0, movingDuration: 0)),
            MovementEstimateCopy.disturbanceText(
                SleepDisturbances(pickups: 1, movingDuration: 300)),
            MovementEstimateCopy.disturbanceText(
                SleepDisturbances(pickups: 4, movingDuration: 900)),
            MovementEstimateCopy.restText(0),
            MovementEstimateCopy.restText(25 * 60),
            MovementEstimateCopy.restText(90 * 60),
            MovementEstimateCopy.restText(5.5 * 3600),
            MovementEstimateCopy.restText(8 * 3600),
        ]
    }

    /// `TARGETED_DEVICE_FAMILY` is `"1,2"`. "Phone moved 3 times overnight" is read by an iPad user about
    /// their iPad, and by a user whose phone was on a charger across the room about a phone they did not
    /// touch. What was measured is *movement*; saying so costs nothing and claims less.
    func testNoSuccessLineNamesASpecificDeviceModel() {
        let models = ["iphone", "ipad", "phone", "apple watch", "watch", "mac"]
        for line in everySuccessLine {
            let lowered = line.lowercased()
            for model in models {
                XCTAssertFalse(
                    lowered.contains(model),
                    "a success line names \"\(model)\" on a universal target: \"\(line)\"")
            }
        }
    }

    /// CoreGlyphs' `symbol_restrictions.strings` records
    /// `iphone.gen1.radiowaves.left.and.right` as usable "only to refer to Apple's iPhone". The section's
    /// success line is about the reader's movement, not about an iPhone, and on iPad it depicts hardware
    /// they do not own — the same defect `testNoIconDepictsASpecificDeviceModel` already forbids for the
    /// unavailable reasons, in the branch that test cannot see.
    func testNoSuccessIconDepictsASpecificDeviceModel() {
        let models = ["iphone", "ipad", "applewatch", "macbook", "desktopcomputer"]
        for icon in [MovementEstimateCopy.restIcon, MovementEstimateCopy.disturbanceIcon] {
            for model in models {
                XCTAssertFalse(
                    icon.contains(model),
                    "the success glyph \"\(icon)\" depicts \(model) on a universal target")
            }
        }
    }

    /// The two lines sit one above the other; sharing a glyph makes them read as one repeated fact.
    func testTheTwoSuccessLinesAreDistinguishable() {
        XCTAssertNotEqual(
            MovementEstimateCopy.restIcon, MovementEstimateCopy.disturbanceIcon,
            "the rest and disturbance lines share a glyph")
    }

    /// #39: an estimate, never a diagnosis. And never a *sleep* claim — a still phone is not a sleeping
    /// person, which is why the domain calls this "low activity" and the caveat line says "estimated from
    /// movement". A success line that said "you slept 5h30m" would make the caveat a contradiction.
    func testNoSuccessLineClaimsSleepOrMakesAClinicalClaim() {
        let forbidden = [
            "slept", "sleep", "asleep", "rem", "deep sleep", "disorder", "diagnos", "doctor",
            "insomnia", "apnea", "quality",
        ]
        for line in everySuccessLine {
            let lowered = line.lowercased()
            for term in forbidden {
                XCTAssertFalse(
                    lowered.contains(term),
                    "a success line claims sleep or makes a clinical claim (\"\(term)\"): \"\(line)\""
                )
            }
        }
    }

    /// Every line is a sentence a groggy reader can act on or ignore — never blank, and never a bare number.
    /// A single space passes an emptiness check and renders as a blank row under the header, which is the
    /// vanished section of WG-318 arriving through the success branch instead of the failure one.
    func testNoSuccessLineIsBlank() {
        for line in everySuccessLine {
            XCTAssertFalse(
                line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "a success line renders blank")
        }
    }

    /// Pluralization and the two rounding boundaries, pinned by value. `restText` states a duration below
    /// half an hour qualitatively — "~12m of low activity overnight" claims a precision an estimate derived
    /// from activity classifications does not have.
    func testCountsAndDurationsReadCorrectlyAtTheirBoundaries() {
        XCTAssertEqual(
            MovementEstimateCopy.disturbanceText(SleepDisturbances(pickups: 0, movingDuration: 0)),
            "No movement detected in that stretch.")
        XCTAssertTrue(
            MovementEstimateCopy.disturbanceText(
                SleepDisturbances(pickups: 1, movingDuration: 300)
            ).contains("1 time"))
        XCTAssertTrue(
            MovementEstimateCopy.disturbanceText(
                SleepDisturbances(pickups: 2, movingDuration: 600)
            ).contains("2 times"))
        XCTAssertEqual(
            MovementEstimateCopy.restText(29 * 60), "Little low-activity time overnight.")
        XCTAssertEqual(MovementEstimateCopy.restText(30 * 60), "~30m of low activity overnight")
        XCTAssertEqual(MovementEstimateCopy.restText(3600), "~1h of low activity overnight")
        XCTAssertEqual(
            MovementEstimateCopy.restText(5.5 * 3600), "~5h 30m of low activity overnight")
    }

    /// **The disturbance count is not a claim about the night.** `ReadinessViewModel` calls
    /// `SleepDisturbanceEstimator.estimate(samples:window:)` with `window: night`, and `nightSpan` closes a
    /// block at the *start* of the run that terminated it — so any awakening longer than `maxDisturbanceGap`
    /// is outside the counting window by construction (WG-313 H4, pinned by
    /// `testALongAwakeningIsCountedRatherThanDeletingItselfFromTheCount`).
    ///
    /// "No overnight movement detected." therefore asserted an undisturbed night on exactly the nights that
    /// were *most* disturbed — a reassuring falsehood on the signal this feature is named for. The copy must
    /// claim only what was counted: movement within the stretch the line above it reports. This is a
    /// prohibition, so `testEveryDisturbanceLineScopesItsClaimToWhatWasCounted` states the positive rule
    /// beside it.
    func testTheZeroCountLineDoesNotClaimAnUndisturbedNight() {
        let line = MovementEstimateCopy.disturbanceText(.none).lowercased()
        for claim in [
            "no overnight movement", "no movement overnight", "undisturbed", "uninterrupted",
            "nothing overnight", "all night",
        ] {
            XCTAssertFalse(
                line.contains(claim),
                """
                the zero-count line claims an undisturbed night ("\(claim)"), but the count excludes any \
                awakening over maxDisturbanceGap: "\(line)"
                """)
        }
    }

    /// The positive half of the rule above: every disturbance line names the stretch it was counted over,
    /// rather than the night. A prohibition alone would be satisfied by dropping the scope entirely.
    func testEveryDisturbanceLineScopesItsClaimToWhatWasCounted() {
        for pickups in [0, 1, 4] {
            let line = MovementEstimateCopy.disturbanceText(
                SleepDisturbances(pickups: pickups, movingDuration: 600))
            XCTAssertTrue(
                line.lowercased().contains("that stretch"),
                """
                the disturbance line for \(pickups) pickups claims more than was counted — it must scope \
                itself to the rest stretch the line above reports: "\(line)"
                """)
        }
    }

    /// `.noNightFound` is reached whenever no block clears `minimumNightDuration`, which includes a **dense,
    /// complete** night of records in a fragmented pattern (WG-313 H4/H5). Asserting a shortage of data is
    /// then simply false, and it sends the reader looking for a permissions or hardware problem that isn't
    /// there. The honest claim is about the pattern: no clear rest period was found.
    ///
    /// The case's own docstring already says this — "this does not assert that any motion data existed" —
    /// so the string contradicted the type it hung off.
    func testTheNoNightReasonDoesNotAssertAShortageOfData() {
        let message = MovementUnavailability.noNightFound.message.lowercased()
        for claim in ["not enough", "no data", "insufficient", "too little", "no movement data"] {
            XCTAssertFalse(
                message.contains(claim),
                """
                .noNightFound asserts a data shortage ("\(claim)") that is false for a dense night in a \
                fragmented pattern: "\(message)"
                """)
        }
    }

    /// Advisory copy only. This card is never allowed to imply the alarm is affected — it holds no alarm
    /// authority and a missing movement estimate changes nothing about scheduling.
    func testNoMessageImpliesTheAlarmIsAffected() {
        for reason in MovementUnavailability.allCases {
            let message = reason.message.lowercased()
            // The product is *called* "Alarm Agent", so a bare `contains("alarm")` flags the display name
            // and would push the next author to weaken the assertion. Strip the name, then check the
            // claims a groggy reader would actually act on — a one-word substring grep was never the
            // safety property this test's name promises.
            let withoutProductName = message.replacingOccurrences(of: "alarm agent", with: "")
            for claim in ["alarm", "wake you", "won't wake", "ring", "go off", "on time"] {
                XCTAssertFalse(
                    withoutProductName.contains(claim),
                    "\(reason) implies the alarm is affected (\"\(claim)\"): \"\(reason.message)\"")
            }
            // Trimmed, not `isEmpty`: a single space passes an emptiness check and renders a blank line
            // under the header — the vanished section reaching the screen *through* the test written to
            // stop it. Reviewers constructed exactly that string.
            XCTAssertFalse(
                reason.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(reason) renders blank, so the section says nothing")
        }
    }

    /// #39: this is a wellness estimate, never a diagnosis. A reason for *missing data* has no business
    /// mentioning conditions or clinicians, and nothing else in this file would stop it — a reviewer passed
    /// all the other assertions with copy suggesting the reader see a doctor about a sleep disorder.
    func testNoMessageMakesADiagnosticOrTreatmentClaim() {
        let clinical = [
            "disorder", "diagnos", "doctor", "physician", "clinician", "symptom", "treat", "apnea",
            "insomnia", "condition", "medical",
        ]
        for reason in MovementUnavailability.allCases {
            let message = reason.message.lowercased()
            for term in clinical {
                XCTAssertFalse(
                    message.contains(term),
                    "\(reason) makes a clinical claim (\"\(term)\"): \"\(reason.message)\"")
            }
        }
    }

    /// The retry instruction the copy dropped must not come back as a picture. `arrow.clockwise` is *the*
    /// iOS refresh affordance; rendered non-interactively beside "we couldn't read your movement data" it
    /// depicts an action this screen cannot perform, which is where `testNoMessageInstructsAGesture…`
    /// cannot see it — that test is scoped to `message`.
    func testNoIconDepictsAnAffordanceTheScreenDoesNotHave() {
        let actionGlyphs = [
            "arrow.clockwise", "arrow.triangle.2.circlepath", "gear", "gearshape", "hand.tap",
            "chevron.right", "arrow.down.circle",
        ]
        for reason in MovementUnavailability.allCases {
            XCTAssertFalse(
                actionGlyphs.contains(reason.icon),
                "\(reason) shows the action glyph \"\(reason.icon)\" on a screen with no such affordance"
            )
        }
    }

    /// `.accessRestricted` is the one reason allowed to name Settings, because it says Settings will **not**
    /// help. The prohibition test's docstring claimed this exemption while its loop did not implement it, so
    /// the copy passed only by phrasing accident — rewording to "Changing this in Settings won't help."
    /// would have failed a test that explicitly blessed it, and the likely next move is to weaken the
    /// assertion. Stated as its own positive requirement instead.
    func testTheRestrictedReasonSaysSettingsWillNotHelp() {
        let message = MovementUnavailability.accessRestricted.message.lowercased()
        XCTAssertTrue(
            message.contains("settings"),
            "restricted access must name Settings in order to rule it out: \"\(message)\"")
        XCTAssertTrue(
            message.contains("won't change this") || message.contains("won't help"),
            "naming Settings without ruling it out reads as an instruction to go there")
    }
}
