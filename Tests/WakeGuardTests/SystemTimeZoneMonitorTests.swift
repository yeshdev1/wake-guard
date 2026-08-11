import Foundation
import XCTest

@testable import WakeGuard

/// WG-100: the device time-zone monitor's launch reconcile. Deterministic and device-zone-independent — it
/// preseeds a last-known zone chosen to differ from the current zone, so `start()` must detect exactly one
/// missed change (the launch reconcile that catches a change made while the app was closed). The live
/// `NSSystemTimeZoneDidChange` subscription itself is device-verified (WG-030).
final class SystemTimeZoneMonitorTests: XCTestCase {

    func testStartReconcilesOnceAgainstAMissedChange() throws {
        let current = try IANATimeZone(TimeZone.current)
        // A preseeded zone guaranteed to differ from the device's current zone, so a change is detected
        // regardless of what the host/simulator zone happens to be.
        let preseed = try IANATimeZone(
            identifier: current.identifier == "Asia/Tokyo" ? "America/New_York" : "Asia/Tokyo")
        let store = InMemoryTimeZoneStateStore(preseed)
        let changes = Synchronized<Int>(0)
        let monitor = SystemTimeZoneMonitor(
            store: store, onChange: { _ in changes.mutate { $0 += 1 } })

        monitor.start()
        monitor.stop()

        XCTAssertEqual(
            changes.get(), 1, "start() reconciles exactly once against the missed change")
    }

    func testGraphComposesTheMonitor() throws {
        // The graph wires the monitor so RootView can start it in production; the in-memory graph composes
        // it but never starts it (hermetic — no NotificationCenter / TimeZone.current touch).
        let env = try AppEnvironment.inMemory()
        _ = env.timeZoneMonitor  // a missing member would fail to compile
    }
}
