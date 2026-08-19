import XCTest

@testable import WakeGuard

/// WG-318: the user-facing copy for every reason the "Movement overnight" section has no estimate.
///
/// The section exists to *say why* it is empty, so its copy is the feature, not decoration — and this branch
/// has already shipped two defects that live entirely in these strings: an instruction to "Pull down to try
/// again" on a screen with no `.refreshable` anywhere in `Sources/`, and a claim about "this iPhone" on a
/// target that also ships to iPad. Neither was reachable from a test while the copy sat in private
/// `ReadinessCardView` methods. Driving `MovementUnavailability.allCases` means a sixth reason cannot be
/// added without its copy being held to the same rules.
final class MovementUnavailabilityCopyTests: XCTestCase {

    // MARK: each reason says what it means

    /// **The load-bearing test in this file.** Every other assertion here is universally quantified over
    /// `allCases`, so all of them constrain only the *multiset* of strings — swap `.sourceUnavailable`'s and
    /// `.noNightFound`'s messages and the other tests stay green while an iPhone user with a full night is
    /// told their hardware can't track movement and the iPad user waits for data that will never arrive.
    /// Both adversarial reviewers found that independently. Prohibitions re-derived from past defects are a
    /// regression net, not evidence that the copy says what the case means.
    ///
    /// The `switch` is exhaustive on purpose: a sixth reason fails to compile until its meaning is stated.
    func testEachReasonStatesItsOwnCause() {
        for reason in MovementUnavailability.allCases {
            let mustSay: String
            switch reason {
            case .sourceUnavailable: mustSay = "can't track movement"
            case .accessUnavailable: mustSay = "doesn't have access"
            case .accessRestricted: mustSay = "restricted"
            case .temporarilyUnavailable: mustSay = "couldn't read"
            // A pattern claim, not a data claim: this case is reached with a dense, complete night of
            // records whenever no block clears `minimumNightDuration` (WG-313 H4/H5), so the previous
            // "not enough movement data" was false exactly there. Pinned by
            // `testTheNoNightReasonDoesNotAssertAShortageOfData`.
            case .noNightFound: mustSay = "couldn't pick out"
            }
            XCTAssertTrue(
                reason.message.lowercased().contains(mustSay),
                """
                \(reason) does not state its own cause — it must contain "\(mustSay)", but reads: \
                "\(reason.message)"
                """)
        }
    }

    // MARK: no claim about a device the user may not own

    /// The product is **"Alarm Agent"** (`INFOPLIST_KEY_CFBundleDisplayName`). "WakeGuard" is the internal
    /// `PRODUCT_NAME` and appears in no other user-facing string in `Sources/` — naming it sends the reader
    /// hunting for an app that is on neither their home screen nor their Settings list. Same defect class as
    /// "This iPhone": naming something the reader does not have.
    func testNoMessageNamesTheInternalProductNameInsteadOfTheDisplayName() {
        for reason in MovementUnavailability.allCases {
            XCTAssertFalse(
                reason.message.contains("WakeGuard"),
                """
                \(reason) names the internal product name; the user sees "Alarm Agent": \
                "\(reason.message)"
                """)
        }
    }

    /// `TARGETED_DEVICE_FAMILY` is `"1,2"` — iPhone **and** iPad. Most iPads have no activity classifier, so
    /// `.sourceUnavailable` is the *only* state an iPad user ever sees in this section, and it named a device
    /// they do not own. Naming a model is never necessary here: every reason is about the device in hand.
    func testNoMessageNamesASpecificDeviceModel() {
        let models = ["iphone", "ipad", "apple watch", "applewatch", "mac"]
        for reason in MovementUnavailability.allCases {
            let message = reason.message.lowercased()
            for model in models {
                XCTAssertFalse(
                    message.contains(model),
                    """
                    \(reason) names "\(model)" on a universal (iPhone + iPad) target, so it can describe a \
                    device the reader does not own: "\(reason.message)"
                    """)
            }
        }
    }

    /// The icon carries the same claim as the text, more quietly. An iPhone glyph beside device-neutral
    /// wording re-states exactly what the wording stopped saying.
    func testNoIconDepictsASpecificDeviceModel() {
        let models = ["iphone", "ipad", "applewatch", "macbook", "desktopcomputer"]
        for reason in MovementUnavailability.allCases {
            for model in models {
                XCTAssertFalse(
                    reason.icon.contains(model),
                    "\(reason) uses the device-specific glyph \"\(reason.icon)\" on a universal target"
                )
            }
        }
    }

    // MARK: no instruction the user cannot carry out

    /// The screen has no `.refreshable`, no scene-phase hook and no retry button, so the only way to re-run
    /// the query is to leave and come back. An instruction to an affordance that does not exist is worse
    /// than no instruction: it silently does nothing and reads as the app ignoring the user.
    func testNoMessageInstructsAGestureTheScreenDoesNotSupport() {
        let absentAffordances = ["pull down", "pull to refresh", "swipe down", "tap to retry"]
        for reason in MovementUnavailability.allCases {
            let message = reason.message.lowercased()
            for affordance in absentAffordances {
                XCTAssertFalse(
                    message.contains(affordance),
                    "\(reason) instructs \"\(affordance)\", which this screen cannot perform")
            }
        }
    }

    /// A Settings instruction is only honest for `.accessUnavailable`, and not even there — `.notDetermined`
    /// collapses into it, and iOS shows no Motion & Fitness row for an app that has never asked. Sending a
    /// user with no motion hardware, or an MDM-restricted one, to a toggle is a guaranteed dead end.
    /// `.accessRestricted` names Settings only to rule it out; that exemption is stated positively by
    /// `testTheRestrictedReasonSaysSettingsWillNotHelp` rather than carved out of this loop, so this test
    /// stays a flat prohibition and neither comment promises a carve-out the code does not implement.
    func testNoMessageSendsTheUserToASettingsToggleThatCannotHelp() {
        let instructions = ["in settings", "open settings", "go to settings", "settings ›"]
        for reason in MovementUnavailability.allCases {
            let message = reason.message.lowercased()
            for instruction in instructions {
                XCTAssertFalse(
                    message.contains(instruction),
                    "\(reason) directs the user to Settings: \"\(reason.message)\"")
            }
        }
    }

    // MARK: the reasons stay distinguishable

    /// The whole point of five reasons is that the user can tell them apart. Two reasons sharing a string or
    /// a glyph is the vanished-section defect at one remove — the section renders, and still says nothing
    /// the user can act on differently.
    func testEveryReasonHasADistinctMessageAndIcon() {
        let messages = MovementUnavailability.allCases.map(\.message)
        let icons = MovementUnavailability.allCases.map(\.icon)
        XCTAssertEqual(
            Set(messages).count, MovementUnavailability.allCases.count,
            "two reasons share the same sentence, so they are indistinguishable on screen")
        XCTAssertEqual(
            Set(icons).count, MovementUnavailability.allCases.count,
            "two reasons share the same glyph")
    }

    /// `moon.zzz` is the rest-estimate icon in the same section, so an unavailable glyph near it reads as a
    /// normal result rather than an absence. Read from `MovementEstimateCopy` rather than re-typed: as
    /// literals these drifted the moment the success glyph changed, and a stale list here quietly permits
    /// the collision it exists to forbid.
    func testNoIconCollidesWithTheSectionsSuccessGlyphs() {
        let successGlyphs = [MovementEstimateCopy.restIcon, MovementEstimateCopy.disturbanceIcon]
        for reason in MovementUnavailability.allCases {
            XCTAssertFalse(
                successGlyphs.contains(reason.icon),
                "\(reason) reuses a success glyph, so an absent estimate looks like a present one")
        }
    }

    /// **No** reason may carry a warning symbol, including `.accessUnavailable`.
    ///
    /// This test previously asserted the opposite — that `.accessUnavailable` *must* be marked with a
    /// triangle, on the reasoning that it is "the only reason the user can act on". Its own docstring then
    /// forbade exactly that: "a warning symbol on a nothing-to-fix state manufactures an alarm with no remedy
    /// behind it". `.accessUnavailable` **is** a nothing-to-fix state as shipped. `.notDetermined` collapses
    /// into it, iOS shows no Motion & Fitness row for an app that has never asked, this screen has no
    /// in-context permission ask, and `MovementUnavailability.message` deliberately offers no instruction —
    /// so the glyph promised an action that exists nowhere in the app, and CI held the promise in place.
    ///
    /// Actionable *in principle* is not the test. A warning is honest only when the reader can do something
    /// about it **from here**, and re-adding the triangle is only correct alongside the affordance it points
    /// at.
    func testNoReasonCarriesAWarningSymbolBecauseNoneOffersARemedy() {
        for reason in MovementUnavailability.allCases {
            XCTAssertFalse(
                reason.icon.contains("exclamationmark"),
                """
                \(reason) is marked with a warning symbol, but its message offers no action this screen \
                supports: "\(reason.message)"
                """)
        }
    }
}
