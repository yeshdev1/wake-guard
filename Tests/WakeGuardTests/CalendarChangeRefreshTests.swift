import Foundation
import XCTest

@testable import WakeGuard

/// WG-147: calendar-change refresh. Verifies **changes invalidate stale proposals** (a change marks the
/// current recommendation stale until a refresh runs), that **prompt frequency is bounded** (refreshes are
/// throttled, so a burst is coalesced), and that **no automatic critical mutation occurs** — refreshing
/// only recomputes the advisory recommendation via an injected closure; the refresher has no alarm path.
@MainActor
final class CalendarChangeRefreshTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func canned() -> TomorrowPlanPresentation {
        TomorrowPlanPresentation(existingAlarmRing: nil, recommendation: nil)
    }

    // MARK: policy

    func testProposalIsStaleWhenOlderThanTheChangeGeneration() {
        let policy = CalendarChangeRefreshPolicy()
        XCTAssertTrue(policy.isProposalStale(proposalGeneration: 0, changeGeneration: 1))
        XCTAssertFalse(policy.isProposalStale(proposalGeneration: 1, changeGeneration: 1))
    }

    func testShouldRefreshRespectsTheMinimumInterval() {
        let policy = CalendarChangeRefreshPolicy(minimumRefreshInterval: 60)
        XCTAssertTrue(
            policy.shouldRefresh(now: base, lastRefreshedAt: nil), "never refreshed → yes")
        XCTAssertFalse(
            policy.shouldRefresh(now: base.addingTimeInterval(30), lastRefreshedAt: base),
            "too soon")
        XCTAssertTrue(policy.shouldRefresh(now: base.addingTimeInterval(60), lastRefreshedAt: base))
    }

    // MARK: changes invalidate stale proposals

    func testACalendarChangeMarksTheCurrentProposalStale() async {
        let refresher = TomorrowPlanRefresher(
            policy: CalendarChangeRefreshPolicy(minimumRefreshInterval: 0)
        ) {
            self.canned()
        }
        _ = await refresher.refreshIfNeeded(now: base)
        XCTAssertFalse(refresher.isStale)
        refresher.calendarChanged()
        XCTAssertTrue(refresher.isStale, "a change invalidates the current recommendation")
    }

    // MARK: prompt frequency is bounded

    func testRefreshIsThrottledAndABurstIsCoalesced() async {
        var recomputeCount = 0
        let refresher = TomorrowPlanRefresher(
            policy: CalendarChangeRefreshPolicy(minimumRefreshInterval: 60)
        ) {
            recomputeCount += 1
            return self.canned()
        }
        let firstRefresh = await refresher.refreshIfNeeded(now: base)
        XCTAssertTrue(firstRefresh)
        XCTAssertEqual(recomputeCount, 1)

        refresher.calendarChanged()
        // Too soon after the last refresh → coalesced.
        let throttled = await refresher.refreshIfNeeded(now: base.addingTimeInterval(30))
        XCTAssertFalse(throttled)
        XCTAssertEqual(
            recomputeCount, 1, "a burst within the interval is coalesced — no extra refresh")
        XCTAssertTrue(refresher.isStale, "stays stale until a refresh is allowed")

        let allowed = await refresher.refreshIfNeeded(now: base.addingTimeInterval(60))
        XCTAssertTrue(allowed)
        XCTAssertEqual(recomputeCount, 2)
        XCTAssertFalse(refresher.isStale)
    }

    // MARK: no automatic critical mutation

    func testRefreshRecomputesTheRecommendationButAppliesNothing() async {
        // A refresh only recomputes the advisory presentation via the injected closure — the refresher has
        // no alarm dependency, so a calendar change can never apply an (automatic, critical) mutation.
        var recomputeCount = 0
        let refresher = TomorrowPlanRefresher(
            policy: CalendarChangeRefreshPolicy(minimumRefreshInterval: 0)
        ) {
            recomputeCount += 1
            return self.canned()
        }
        refresher.calendarChanged()
        _ = await refresher.refreshIfNeeded(now: base)
        XCTAssertEqual(recomputeCount, 1, "recompute produced a new recommendation, nothing more")
        XCTAssertNotNil(refresher.presentation)
    }
}
