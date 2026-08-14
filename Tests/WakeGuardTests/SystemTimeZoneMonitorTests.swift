import Foundation
import XCTest

@testable import WakeGuard

/// WG-100: the device time-zone monitor's launch reconcile. Deterministic and device-zone-independent — it
/// preseeds a last-known zone chosen to differ from the current zone, so `start()` must detect exactly one
/// missed change (the launch reconcile that catches a change made while the app was closed). The live
/// `NSSystemTimeZoneDidChange` subscription itself is device-verified (WG-030).
final class SystemTimeZoneMonitorTests: XCTestCase {

    func testStartReconcilesOnceAgainstAMissedChange() throws {
        // The current zone is INJECTED (not read from the host): a CI runner sits in UTC — a non-IANA
        // zone the domain rejects by design (#11) — which made the old host-dependent version fail
        // there while passing on any geographic machine. Fixed zones make it deterministic everywhere.
        let store = InMemoryTimeZoneStateStore(try IANATimeZone(identifier: "America/New_York"))
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let changes = Synchronized<Int>(0)
        let monitor = SystemTimeZoneMonitor(
            store: store, onChange: { _ in changes.mutate { $0 += 1 } },
            currentZone: { tokyo })

        monitor.start()
        monitor.stop()

        XCTAssertEqual(
            changes.get(), 1, "start() reconciles exactly once against the missed change")
    }

    func testNonIANACurrentZoneIsSkippedFailClosed() throws {
        // The CI environment itself, pinned: a UTC/fixed-offset current zone (#11) fires no change and
        // never crashes — the monitor skips fail-closed until a geographic zone is readable.
        let store = InMemoryTimeZoneStateStore(try IANATimeZone(identifier: "America/New_York"))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let changes = Synchronized<Int>(0)
        let monitor = SystemTimeZoneMonitor(
            store: store, onChange: { _ in changes.mutate { $0 += 1 } },
            currentZone: { utc })

        monitor.start()
        monitor.stop()

        XCTAssertEqual(changes.get(), 0, "a non-IANA zone is skipped, never a spurious change")
    }

    func testGraphComposesTheMonitor() throws {
        // The graph wires the monitor so RootView can start it in production; the in-memory graph composes
        // it but never starts it (hermetic — no NotificationCenter / TimeZone.current touch).
        let env = try AppEnvironment.inMemory()
        _ = env.timeZoneMonitor  // a missing member would fail to compile
    }
}
