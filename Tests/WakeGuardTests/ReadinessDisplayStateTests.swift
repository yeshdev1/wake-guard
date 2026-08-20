import Foundation
import XCTest

@testable import WakeGuard

/// WG-319: what the readiness card **shows**, as distinct from what the view model *holds*.
///
/// Written because a mutation survived. `ReadinessCardLoadBoundTests` asserts `model.readiness`, which is the
/// view model's state; `ReadinessScreen` branches on `model.readiness.cardContent`, and rewriting that
/// property's `.unavailable` arm to `return nil` left the **entire suite green** while restoring WG-319's
/// original defect exactly: the spinner stays on screen for as long as the reader stays on it, with no query
/// in flight, hiding the whole card including the always-on movement section WG-318 exists to guarantee.
///
/// So the state machine was covered and its one user-visible consequence was not. `cardContent` is the last
/// seam **this target** can reach — the `if let` in `ReadinessScreen` that consumes it stays uncovered here,
/// and that is a stated limitation rather than a thing this file pretends to check.
///
/// An earlier version of this comment said "there is no UI test target", which is **false**: `project.yml`
/// declares `WakeGuardUITests` and `UITests/ScreenshotTourUITests.swift` already taps into this very screen.
/// What is true is narrower and more useful — the tour only ever reaches the `.assessed` branch, so the
/// `.unavailable` branch is what nothing exercises end to end, and `make test-ui` is not part of `ci` or
/// `ci-fast`. Closing that seam is a launch argument and one assertion in the existing tour, not new
/// infrastructure; it is deliberately not done here, and it is the first gap worth closing next.
///
/// The copy tests are `MovementUnavailabilityCopyTests` applied to the sibling type, for the reason that file
/// gives: copy no test can reach is copy no rule applies to, and every defect this branch has shipped in six
/// rounds lived in a string.
final class ReadinessDisplayStateTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// A readiness with real factors, so "an assessment reached the card" is a value and not a sentinel a
    /// presence check would flatter.
    private func assessmentWithFactors() -> ReadinessAssessment {
        let start = base.addingTimeInterval(-86_400)
        let samples = [
            SleepSample(
                category: .asleep,
                interval: DateInterval(start: start, end: start.addingTimeInterval(7 * 3_600)))
        ]
        return ReadinessComputer.readiness(from: samples, need: .default, calendar: makeCalendar())
    }

    // MARK: - The spinner belongs to `.loading` and to nothing else

    /// **The load-bearing test in this file** — the one the surviving mutant needed.
    ///
    /// `ReadinessScreen` shows `ProgressView("Checking your sleep readiness…")` exactly when `cardContent` is
    /// `nil`, so this property *is* the spinner's condition. A read that concluded must therefore produce
    /// content, whatever it concluded: the whole of WG-319 is that a query which will never answer must stop
    /// claiming to be working on it.
    ///
    /// The `switch` is exhaustive on purpose: a fourth display state cannot be added without stating whether
    /// it is allowed to hold the spinner.
    func testOnlyLoadingWithholdsTheCardSoAConcludedReadAlwaysRendersOne() {
        let assessment = assessmentWithFactors()
        let states: [ReadinessDisplayState] =
            [.loading, .assessed(assessment)]
            + ReadinessUnavailability.allCases.map(ReadinessDisplayState.unavailable)

        for state in states {
            switch state {
            case .loading:
                XCTAssertNil(
                    state.cardContent,
                    """
                    the query is genuinely in flight here, and this is the only state where \
                    "Checking your sleep readiness…" is true
                    """)
            case .assessed(let assessment):
                XCTAssertEqual(
                    state.cardContent, .assessed(assessment),
                    "a read that answered must reach the card, carrying the assessment it produced")
            case .unavailable(let reason):
                XCTAssertEqual(
                    state.cardContent, .unavailable(reason),
                    """
                    \(reason) concluded the read, so the card must render and say so — withholding it \
                    leaves a permanent spinner with no query behind it, which is the defect WG-319 exists \
                    to remove, and hides the always-on movement section with it
                    """)
            }
        }
    }

    // MARK: - The reason says what happened

    /// Round seven's rule, applied to the sibling type while it still has one case: an **exhaustive positive**
    /// claim about what each reason must say, not a set of prohibitions. A prohibition suite constrains the
    /// multiset of strings and never the case-to-meaning binding, so it stays green when two cases swap
    /// messages. A second reason here cannot compile until its meaning is stated.
    func testEachReasonStatesItsOwnCause() {
        for reason in ReadinessUnavailability.allCases {
            let mustSay: String
            switch reason {
            // States that the **read** failed. It deliberately makes no claim about the user's data,
            // because a read that never concluded established nothing about it.
            case .temporarilyUnavailable: mustSay = "couldn't check"
            }
            XCTAssertTrue(
                reason.message.lowercased().contains(mustSay),
                """
                \(reason) does not state its own cause — it must contain "\(mustSay)", but reads: \
                "\(reason.message)"
                """)
        }
    }

    /// Blank copy satisfies every prohibition in this file at once. `MovementUnavailability`'s suite was
    /// passed by `" "` — silence reaching the screen through the tests written to prevent silence — so the
    /// floor is checked explicitly rather than left to the assertions above.
    func testNoMessageIsBlankOrPunctuationOnly() {
        for reason in ReadinessUnavailability.allCases {
            XCTAssertGreaterThan(
                reason.message.trimmingCharacters(in: .whitespacesAndNewlines).count, 10,
                "\(reason) renders effectively nothing: \"\(reason.message)\"")
            XCTAssertFalse(
                reason.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(reason) has no glyph, so the state is conveyed by text alone")
        }
    }

    // MARK: - It must not claim anything about the user's sleep data

    /// **Round twelve, finding 1 — pinned as a rule rather than as one repro.** The cold-open degrade used to
    /// resolve the spinner by writing `readiness(from: [])`, which told a user with fourteen nights in
    /// HealthKit and a hung `HKSampleQuery` that there isn't enough sleep data yet and instructed them to add
    /// more. Nothing had been read; every one of those sentences was a claim about data the query never
    /// looked at.
    ///
    /// `ReadinessCardLoadBoundTests` pins that the degrade no longer *routes* to that copy. This pins that the
    /// copy it routes to instead never acquires the same claim — the two are different questions, and the
    /// first was already true on the day the second was false.
    func testNoMessageMakesAClaimAboutHowMuchSleepDataTheUserHas() {
        let dataClaims = ["enough", "sleep data", "add a few nights", "more data", "no data"]
        for reason in ReadinessUnavailability.allCases {
            let message = reason.message.lowercased()
            for claim in dataClaims {
                XCTAssertFalse(
                    message.contains(claim),
                    """
                    \(reason) says "\(claim)", which is a statement about the user's sleep data made from a \
                    read that returned nothing: "\(reason.message)"
                    """)
            }
        }
    }

    // MARK: - No instruction the reader cannot carry out

    /// The screen has no `.refreshable`, no scene-phase hook and no retry button. This branch has already
    /// shipped that instruction twice on the sibling path — once as a sentence, once as `arrow.clockwise`,
    /// which re-states it as a glyph.
    func testNoMessageOrIconOffersARetryTheScreenCannotPerform() {
        let absentAffordances = [
            "pull down", "pull to refresh", "swipe down", "tap to retry", "try again",
        ]
        for reason in ReadinessUnavailability.allCases {
            let message = reason.message.lowercased()
            for affordance in absentAffordances {
                XCTAssertFalse(
                    message.contains(affordance),
                    "\(reason) instructs \"\(affordance)\", which this screen cannot perform")
            }
            XCTAssertNotEqual(
                reason.icon, "arrow.clockwise",
                "\(reason) uses the iOS retry glyph, which promises the gesture the message avoids")
        }
    }

    /// A Settings instruction is a guaranteed dead end here, and for a sharper reason than on the movement
    /// path: HealthKit does not reveal read denial, so this state is reached with access **granted** — the
    /// read simply failed. Sending that reader to a Health toggle that is already on is worse than silence.
    func testNoMessageSendsTheUserToASettingsToggleThatCannotHelp() {
        let instructions = [
            "in settings", "open settings", "go to settings", "settings ›", "permission",
        ]
        for reason in ReadinessUnavailability.allCases {
            let message = reason.message.lowercased()
            for instruction in instructions {
                XCTAssertFalse(
                    message.contains(instruction),
                    "\(reason) directs the user to Settings: \"\(reason.message)\"")
            }
        }
    }

    /// The product is **"Alarm Agent"** (`INFOPLIST_KEY_CFBundleDisplayName`); "WakeGuard" is the internal
    /// `PRODUCT_NAME` and appears in no other user-facing string in `Sources/`. Shipped once already, inside
    /// the fix for the defect one row above.
    func testNoMessageNamesTheInternalProductNameInsteadOfTheDisplayName() {
        for reason in ReadinessUnavailability.allCases {
            XCTAssertFalse(
                reason.message.contains("WakeGuard"),
                "\(reason) names the internal product name; the user sees \"Alarm Agent\"")
        }
    }

    /// A warning symbol is honest only when the reader can act **from here**, and there is nothing to act on:
    /// the read failed, the app will retry when the screen is next opened, and no setting changes that. The
    /// sibling suite had this assertion inverted for four rounds, requiring a triangle on a nothing-to-fix
    /// state.
    func testNoReasonCarriesAWarningSymbolBecauseNoneOffersARemedy() {
        for reason in ReadinessUnavailability.allCases {
            XCTAssertFalse(
                reason.icon.contains("exclamationmark"),
                """
                \(reason) is marked with a warning symbol, but offers no action this screen supports: \
                "\(reason.message)"
                """)
        }
    }

    /// This card is advisory and touches no alarm state, so it must not imply otherwise. A sleep-readiness
    /// read that failed says nothing about whether an alarm is scheduled, and a groggy reader who infers
    /// that it does is being alarmed by an advisory screen.
    func testNoMessageImpliesTheAlarmIsAffected() {
        for reason in ReadinessUnavailability.allCases {
            XCTAssertFalse(
                reason.message.lowercased().contains("alarm"),
                """
                \(reason) mentions the alarm from a card that holds no alarm authority: \
                "\(reason.message)"
                """)
        }
    }

    // MARK: - The two failure lines share a card

    /// A failed sleep read and a failed motion read render **at the same time, on the same card** — the
    /// readiness line above the divider, the movement line below it. Identical sentences would read as one
    /// message duplicated by a bug rather than as two things that separately didn't work.
    ///
    /// The rule is *distinct*, not *unrelated*: they describe the same epistemic state and are deliberately
    /// parallel in shape, so this asserts they differ in the noun, which is the part that carries the
    /// information.
    func testTheReadinessAndMovementFailureLinesAreNotTheSameSentence() {
        let movementMessages = Set(MovementUnavailability.allCases.map(\.message))
        for reason in ReadinessUnavailability.allCases {
            XCTAssertFalse(
                movementMessages.contains(reason.message),
                """
                \(reason) repeats a movement message verbatim; both can be on screen at once, so the card \
                would state the same sentence twice: "\(reason.message)"
                """)
        }
    }
}
