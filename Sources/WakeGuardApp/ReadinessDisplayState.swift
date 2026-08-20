import Foundation

/// What the readiness **card** is currently showing (WG-319) — as distinct from what a sleep read
/// *returned*, which is `SleepReadOutcome`. The `MovementDisplayState` / `MovementSummary` split, applied one
/// layer up, and for the same reason: `.cancelled` is an outcome that can never be rendered ("keep showing
/// whatever was already there") and `.loading` is a screen state no query can return.
///
/// It replaces a bare `ReadinessAssessment?`. That optional carried two different meanings — "no read has
/// concluded yet" and "a read concluded and there is nothing to show" — and the card distinguished them by
/// rendering the *second* meaning's copy for both. A user with fourteen nights in HealthKit and a hung
/// `HKSampleQuery` was told there isn't enough sleep data yet.
enum ReadinessDisplayState: Equatable, Sendable {
    /// No read has concluded yet. Not an error and not an empty result — the query is still running, so the
    /// screen's `ProgressView("Checking your sleep readiness…")` is honest here and only here.
    case loading
    /// A read concluded. **Including one that found nothing:** an assessment with no factors means HealthKit
    /// answered and had no sleep to report, which is a fact about the user's data and is exactly what
    /// "There isn't enough sleep data yet" was written to say.
    case assessed(ReadinessAssessment)
    /// A read did not produce an assessment we can stand behind, plus what to tell the user about why.
    case unavailable(ReadinessUnavailability)

    /// What to hand the card, or `nil` while still loading — the screen shows its own spinner then and does
    /// not build a card at all.
    var cardContent: ReadinessCardContent? {
        switch self {
        case .loading: return nil
        case .assessed(let assessment): return .assessed(assessment)
        case .unavailable(let reason): return .unavailable(reason)
        }
    }
}

/// What the card renders where the readiness explanation goes (WG-319).
///
/// Deliberately **not** `ReadinessDisplayState`: there is no `.loading` case, because the card does not exist
/// until a read concludes. Handing the card a state it cannot honestly render is the shape `MovementSummary`
/// and `MovementDisplayState` were split to avoid — "an unrenderable case in the view's state is exactly how
/// the section came to render nothing".
enum ReadinessCardContent: Equatable, Sendable {
    case assessed(ReadinessAssessment)
    case unavailable(ReadinessUnavailability)
}

/// Why the readiness card has no assessment to show (WG-319) — the counterpart to `MovementUnavailability`,
/// and held to the same copy rules, which is the point of it existing as a type rather than as a string in
/// the view. Copy no test can reach is copy no rule applies to.
enum ReadinessUnavailability: Equatable, Sendable, CaseIterable {
    /// The read did not conclude, or concluded in an error. Either way **nothing was read**, so there is no
    /// claim to make about the user's data — only about the read.
    ///
    /// One case covers the timeout, the cancellation and the query error because they are one situation for
    /// the reader: the app could not check, and there is nothing for them to change. The distinction between
    /// them lives in `SleepReadOutcome`, where it decides *whether to apply* this state, not in what it says.
    ///
    /// **Known limitation (WG-321): a fourth cause reaches this arm, and for it "just now" is false.** On a
    /// **restricted** device (MDM / parental controls) `HKHealthStore.requestAuthorization` throws,
    /// `HealthKitAuthorizationAdapter` fails closed to `.restricted`, `ReadinessScreen` discards that result,
    /// and the query then errors — arriving here as `.failed`. That failure is permanent and unfixable, not
    /// momentary, so the reader is told to wait for something that will never resolve. The sibling type does
    /// model it (`MovementUnavailability.accessRestricted`, "Settings won't change this"), and the asymmetry
    /// is deliberate for now: closing it means threading the authorization result the screen throws away,
    /// which is exactly the plumbing WG-320's re-scope rejected on the neighbouring path. Filed, not
    /// overlooked — and note the enumeration above says *three* causes while this arm catches four.
    ///
    /// A **denied or revoked grant is deliberately not here.** HealthKit does not reveal read denial — an
    /// unauthorized read returns an empty sample set, not an error — so it arrives as `.samples([])` and is
    /// indistinguishable from "no data" at this layer by Apple's design.
    ///
    /// **No other layer knows either**, and an earlier version of this comment claimed one did
    /// (`HealthAuthorizationCoordinator` "does know the difference and the screen currently discards it").
    /// False, and falsified by the sentence directly above it: `HKHealthStore.requestAuthorization` does not
    /// throw when the user taps Don't Allow, so `HealthKitAuthorizationAdapter` maps Allow *and* Don't Allow
    /// to `.authorized` — as its own docstring says — and the summary folds to `.granted` either way. The
    /// screen has no discarded answer to wire up. The limitation is genuinely framework-imposed at every
    /// layer, which is why the fix filed as WG-320 is to the **copy** on the empty-result path, not to the
    /// plumbing: a card that says "access is off" when it is on is the defect this type exists to prevent,
    /// and a card that can only guess must not assert either way.
    case temporarilyUnavailable

    /// Says what happened and asks the user to change nothing, because there is nothing here they can change.
    ///
    /// **No retry instruction.** This screen has no `.refreshable` and no scene-phase hook, so "pull down to
    /// try again" would be an action that silently does nothing — the defect WG-318 removed from the sibling
    /// path twice, once as a sentence and once as a glyph.
    var message: String {
        switch self {
        case .temporarilyUnavailable:
            // Mirrors `MovementUnavailability.temporarilyUnavailable`'s "We couldn't read your movement data
            // just now." — same epistemic state, same screen, so it must not read as a different kind of
            // problem. It states the *read* failed and asserts nothing about how much sleep data exists,
            // which is the whole correction: the sentence it replaces ("There isn't enough sleep data yet…")
            // was a claim about data the query never looked at.
            "We couldn't check your sleep readiness just now."
        }
    }

    /// **Not** `arrow.clockwise`: that is *the* iOS retry affordance, and the message deliberately instructs
    /// no retry because this screen has none — a refresh glyph would re-state in a symbol the instruction the
    /// text is written to avoid. Matches the sibling reason's glyph for the same reason the copy matches.
    var icon: String {
        switch self {
        case .temporarilyUnavailable: "xmark.circle"
        }
    }
}
