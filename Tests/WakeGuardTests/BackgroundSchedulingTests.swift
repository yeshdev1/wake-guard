import Foundation
import XCTest

@testable import WakeGuard

/// WG-225: location & background scheduling. Verifies **background requests are not spammed** (the
/// reschedule interval is bounded/clamped), that **travel survives throttling** (significant-location, and
/// the runner holds no alarm authority so a critical alarm never depends on a BG run), and that there is
/// **no continuous GPS**.
final class BackgroundSchedulingTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func strippedCode(of relative: String) throws -> String {
        let contents = try String(
            contentsOf: repoRoot().appendingPathComponent(relative), encoding: .utf8)
        var result = ""
        for raw in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") {
                continue
            }
            if let comment = line.range(of: "//") {
                result += line[line.startIndex..<comment.lowerBound] + "\n"
            } else {
                result += line + "\n"
            }
        }
        return result
    }

    // MARK: not spammed

    func testBackgroundRescheduleIntervalIsBoundedAndClamped() {
        XCTAssertGreaterThanOrEqual(PreAlarmBackgroundRunner.Config.default.minimumReschedule, 60)
        // A too-small or non-finite value clamps up, so submissions can't tight-loop.
        XCTAssertEqual(PreAlarmBackgroundRunner.Config(minimumReschedule: 5).minimumReschedule, 900)
        XCTAssertEqual(
            PreAlarmBackgroundRunner.Config(minimumReschedule: .infinity).minimumReschedule, 900)
    }

    func testNextRequestIsAtLeastTheMinimumRescheduleAway() {
        let runner = PreAlarmBackgroundRunner(config: .default)
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertGreaterThanOrEqual(runner.nextRequestTime(after: now).timeIntervalSince(now), 60)
    }

    // MARK: survives throttling / no continuous GPS

    func testTravelUsesSignificantLocationNotContinuousGPS() throws {
        let code = try strippedCode(
            of: "Sources/TravelInfrastructure/CoreLocationSignificantLocationAdapter.swift")
        XCTAssertTrue(code.contains("startMonitoringSignificantLocationChanges"))
        XCTAssertFalse(code.contains("startUpdatingLocation"), "no continuous GPS")
    }

    func testBackgroundRunnerHoldsNoAlarmAuthority() throws {
        let code = try strippedCode(of: "Sources/AlarmApplication/PreAlarmBackgroundRunner.swift")
        // Type-level authority: the runner depends on none of these, so it can't mutate an alarm. (It may
        // call `Task.cancel()` for expiration — that is not alarm authority.)
        for authority in [
            "AlarmManager", "AlarmCommandProcessing", "AlarmPolicyEngine", "AlarmSchedulingEngine",
            "any AlarmRepository", "AlarmCommand",
        ] {
            XCTAssertFalse(
                code.contains(authority),
                "the background runner must be opportunistic and hold no alarm authority ('\(authority)')"
            )
        }
    }
}
