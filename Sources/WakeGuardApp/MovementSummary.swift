import Foundation

/// The outcome of **one** movement refresh (WG-318) — a single total value.
///
/// The section previously carried two independent optionals (`estimatedDisturbances` and
/// `movementUnavailability`) written by separate statements, with only a doc comment asserting that exactly
/// one of them is set. Nothing enforced it: `nightSpan`, `estimate` and `longestRestWindow` are three
/// functions with three failure conditions, so "no estimate **and** no reason" was representable — and that
/// state renders as the section silently disappearing, which is the bug WG-318 exists to remove. Making the
/// refresh return one value moves the invariant from the comment into the type.
///
/// It also makes the refresh a single assignment. Clearing the estimates *before* the query meant every
/// refresh blanked a populated section for as long as the query took.
enum MovementSummary: Equatable, Sendable {
    /// An estimate to show. `rest` is **not** optional: it comes from the same samples and the same night
    /// window as the disturbance count, so "one but not the other" is not a real state to model.
    case available(SleepDisturbances, rest: TimeInterval)
    /// No estimate, plus what the user should be told about why.
    case unavailable(MovementUnavailability)
    /// The refresh was cancelled before it read anything — **not a result**. The previous summary stands;
    /// replacing it would erase a good estimate in order to say nothing.
    case cancelled
    /// The deadline won the race before the source answered — also **not a result**, and handled exactly as
    /// `.cancelled` is.
    ///
    /// Its own case rather than `.unavailable(.temporarilyUnavailable)`: as an `.unavailable` it was applied
    /// unconditionally, so a timeout erased a correct estimate and replaced it with a failure carrying no
    /// retry instruction, on a screen with no `.refreshable`. That contradicted the ADR's assumption (b),
    /// which the neighbouring `.cancelled` case implements. Its own case rather than reusing `.cancelled`
    /// too: the cause differs, and collapsing them would make a *cancelled* refresh indistinguishable from a
    /// *hung* one in every future reader of this type.
    case timedOut
}

/// What the "Movement overnight" section is currently showing (WG-318) — as distinct from what a query
/// *returned*, which is `MovementSummary`.
///
/// The two enums are deliberately not one. `.cancelled` is a query outcome that can never be rendered (it
/// means "keep showing whatever was already there"), and `.loading` is a screen state no query can return.
/// Collapsing them would make each enum carry a case its own domain has no meaning for — and an
/// unrenderable case in the view's state is exactly how the section came to render nothing.
///
/// It starts at `.loading` rather than at some empty state because that is the truth on a cold open:
/// `refresh` publishes `assessment` before awaiting the motion query, so the card is on screen, with the
/// section visible, for the whole duration of that query. Both estimate and reason were `nil` then, so the
/// section rendered nothing on **every** first open — WG-318's own defect, in its most-hit window.
enum MovementDisplayState: Equatable, Sendable {
    /// No result has arrived yet. Not an error and not an empty result — the query is still running.
    case loading
    /// An estimate to show, from a resolved night.
    case available(SleepDisturbances, rest: TimeInterval)
    /// No estimate, plus what the user should be told about why.
    case unavailable(MovementUnavailability)
}

/// Why the "Movement overnight" section has no estimate to show (WG-318). These are genuinely different
/// situations with different (or no) user actions, and silently hiding the section conflated all of them.
/// The distinction is the point: telling a user with a barometer-less device to flip a Settings toggle, or
/// telling a user whose grant is fine that their access is off, is worse than saying nothing.
enum MovementUnavailability: Equatable, Sendable, CaseIterable {
    /// No motion source is wired, or the hardware can't report activity at all. Nothing to fix.
    case sourceUnavailable
    /// Motion & Fitness is off **or not yet granted** — `MotionActivity.forMotionActivity` collapses
    /// `.notDetermined` into `.notAuthorized`, so this reaches a fresh install too. The only reason a user
    /// can in principle act on, and even so the copy does **not** send them to Settings: iOS shows no Motion
    /// & Fitness row for an app that has never asked, and there is no in-context ask on this screen yet.
    case accessUnavailable
    /// Parental controls / MDM forbid motion access. Not actionable — a Settings toggle won't change it,
    /// so it must not be reported as `.accessUnavailable`.
    case accessRestricted
    /// Present and authorized, but the read failed this time. Transient — try again, change nothing.
    case temporarilyUnavailable
    /// The query succeeded but nothing in what came back resolves a night. Not an error. Note this covers an
    /// **empty** sample set as well as a populated one — a source that is present and authorized can simply
    /// have no records for the window (pinned by the "empty history → no night" test), so this does not
    /// assert that any motion data existed, only that the read did not fail.
    case noNightFound
}

/// The two lines the "Movement overnight" section shows when it **does** have an estimate (WG-310/311).
///
/// Here rather than private to `ReadinessCardView` for the same reason `MovementUnavailability.message`
/// moved: copy that no test can reach is copy no rule applies to. The consequence was concrete — the
/// unavailable reasons were held to "name no device model the reader may not own" while the success branch,
/// on the same screen, in the same section, sat outside every one of those tests.
enum MovementEstimateCopy {
    /// The rest-window glyph. Shared with nothing else in the section, so the two lines stay distinguishable
    /// at a glance for a groggy reader.
    static let restIcon = "moon.zzz"

    /// The disturbance glyph. `figure.walk.motion` depicts *movement*, which is what was measured.
    ///
    /// **Not** `iphone.gen1.radiowaves.left.and.right`: CoreGlyphs' `symbol_restrictions.strings` records
    /// that symbol as usable "only to refer to Apple's iPhone", and this target also ships to iPad
    /// (`TARGETED_DEVICE_FAMILY` is `"1,2"`). It is the same defect the unavailable copy already fixed twice
    /// — naming a device the reader may not own — surviving in the one branch no test was watching.
    static let disturbanceIcon = "figure.walk.motion"

    /// A disturbance count, stated as movement rather than as a phone. Nothing here is a sleep claim: the
    /// caveat line beneath says "estimated from movement", and the count is of *device* motion episodes.
    ///
    /// **Scoped to "that stretch", not to the night.** `ReadinessViewModel` counts with `window: night`, and
    /// `nightSpan` closes a block at the *start* of the run that ended it — so an awakening longer than
    /// `maxDisturbanceGap` is excluded from its own count by construction (WG-313 H4). This line previously
    /// read "No overnight movement detected.", which asserted an undisturbed night on precisely the nights
    /// that were most disturbed. It now claims only what was measured: movement inside the rest stretch the
    /// line above reports. The estimator's under-counting bias is defensible ("a missed disturbance is
    /// harmless"); a sentence stating the absence as fact is not.
    static func disturbanceText(_ disturbances: SleepDisturbances) -> String {
        guard disturbances.pickups >= 1 else { return "No movement detected in that stretch." }
        let times = disturbances.pickups == 1 ? "1 time" : "\(disturbances.pickups) times"
        return "Movement detected \(times) in that stretch"
    }

    /// The longest low-activity stretch, rounded to minutes and stated with a `~`. Under half an hour it is
    /// stated qualitatively — "~12m of low activity" invites a precision the estimate does not have.
    static func restText(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        guard totalMinutes >= 30 else { return "Little low-activity time overnight." }
        let (hours, minutes) = (totalMinutes / 60, totalMinutes % 60)
        let span =
            hours >= 1 ? (minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h") : "\(minutes)m"
        return "~\(span) of low activity overnight"
    }
}

extension MovementUnavailability {
    /// Says what happened and, only where there is one, what the user can do about it. Each reason gets its
    /// own sentence because the actions differ: a Settings toggle fixes exactly one of them.
    ///
    /// Copy lives on the reason rather than in the card (the `WellnessSafetyCopy` pattern) so it can be
    /// asserted directly. It was previously private to `ReadinessCardView`, unreachable from a test, and this
    /// branch has already shipped one unfollowable instruction ("Pull down to try again", on a screen with no
    /// `.refreshable`) and one false device claim into it.
    var message: String {
        switch self {
        case .sourceUnavailable:
            // "This device", not "This iPhone": `TARGETED_DEVICE_FAMILY` is `"1,2"` and most iPads have no
            // activity classifier, so this is the **only** state an iPad user ever reaches in this section —
            // the one reader guaranteed to see it was the one being told about a device they don't own.
            "This device can't track movement, so there's no overnight estimate."
        case .accessUnavailable:
            // Deliberately does **not** say "access is off". `.notAuthorized` covers `.notDetermined` too
            // (MotionActivity.forMotionActivity), so on a fresh install this reaches a user who has never
            // denied anything — and iOS shows no Motion & Fitness row for an app that has never asked, so
            // "turn it on in Settings" would be an instruction they cannot follow.
            // "Alarm Agent", the display name (`INFOPLIST_KEY_CFBundleDisplayName`) — **not** "WakeGuard",
            // which is the internal `PRODUCT_NAME` and appears in no other user-facing string in `Sources/`.
            // Naming the target would send the reader looking for an app that isn't on their home screen or
            // in their Settings list: the same defect as "This iPhone", in the same sentence set.
            "Alarm Agent doesn't have access to your movement data, so there's no overnight estimate."
        case .accessRestricted:
            """
            Motion & Fitness access is restricted on this device, so there's no overnight estimate. \
            Settings won't change this.
            """
        case .temporarilyUnavailable:
            // No retry instruction: this screen has no `.refreshable` and no scene-phase hook, so the only
            // way to re-run the query is to leave and come back. Telling the user to pull down would be an
            // action that silently does nothing.
            "We couldn't read your movement data just now."
        case .noNightFound:
            // A claim about the **pattern**, not about the data. This case is reached whenever no block
            // clears `minimumNightDuration`, which includes a dense, complete night of records in a
            // fragmented pattern (WG-313 H4/H5) — so "Not enough movement data" was simply false there, and
            // it sent the reader hunting for a permissions or hardware fault that does not exist. The case's
            // own docstring already said as much ("this does not assert that any motion data existed"), so
            // the string contradicted the type it hangs off.
            "We couldn't pick out a clear rest period last night."
        }
    }

    /// Distinct from the section's success icons — `moon.zzz` is the rest estimate, so an unavailable state
    /// one glyph away from it (`moon.zzz.fill`) read as a normal result.
    ///
    /// **No reason carries a warning symbol.** `.accessUnavailable` used to, on the grounds that it is the
    /// only reason a user can act on *in principle* — but nothing on this screen lets them act. Its message
    /// deliberately gives no instruction (`.notDetermined` collapses into this case, and iOS shows no Motion
    /// & Fitness row for an app that has never asked), and there is no in-context permission prompt here. A
    /// triangle beside a sentence offering no remedy is an alarm with nothing behind it, on a card that is
    /// advisory and touches no alarm state. The glyph comes back when the affordance does, not before.
    var icon: String {
        switch self {
        // `nosign` rather than `iphone.slash`: the glyph carried the same iPhone-only claim the copy just
        // dropped, and "nothing here to fix" is what this reason actually means.
        case .sourceUnavailable: "nosign"
        // `hand.raised` is iOS's own privacy glyph: it depicts *withheld access*, which is what happened,
        // without depicting a remedy (`gearshape` would) or an urgency (a triangle did).
        case .accessUnavailable: "hand.raised"
        case .accessRestricted: "lock"
        // **Not** `arrow.clockwise`: that is *the* iOS retry affordance, and the message deliberately
        // instructs no retry because this screen has none. A refresh glyph beside it re-states in a symbol
        // the instruction the text was rewritten to drop — "Pull down to try again" surviving as a picture.
        case .temporarilyUnavailable: "xmark.circle"
        case .noNightFound: "questionmark.circle"
        }
    }

    /// What to tell the user about a failed motion-history query.
    ///
    /// The catch site used to report **every** non-cancellation throw as `.accessUnavailable`, which is
    /// wrong in three reachable ways: `CoreMotionActivityHistoryAdapter` throws
    /// `.unavailable(.temporarilyUnavailable)` *after* confirming access is granted (so the user is sent to
    /// fix a toggle that is already on), `.unavailable(.notPresent)` on a device with no activity hardware
    /// (the `.sourceUnavailable` copy was written for exactly that user), and `.unavailable(.restricted)`
    /// where the toggle is not the user's to flip. The payload was already there; it just wasn't read.
    static func from(_ error: any Error) -> MovementUnavailability {
        // A throw that isn't a motion-source failure carries no availability claim, so the honest reading
        // is "the read failed", not "your permissions are wrong".
        guard case let MotionSourceError.unavailable(availability) = error else {
            return .temporarilyUnavailable
        }
        switch availability {
        case .notPresent: return .sourceUnavailable
        case .notAuthorized: return .accessUnavailable
        case .restricted: return .accessRestricted
        // `.available` cannot accompany a throw from the adapter, but a source that fails while claiming
        // to be available is by definition a transient failure, not a permission problem.
        case .temporarilyUnavailable, .available: return .temporarilyUnavailable
        }
    }
}
