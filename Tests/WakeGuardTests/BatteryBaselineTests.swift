import Foundation
import XCTest

@testable import WakeGuard

/// WG-223: overnight battery baseline. Detects **continuous-sensing regressions** (the drivers of overnight
/// drain) statically — the location sensing must stay low-power (significant-location only, never continuous
/// GPS) — and checks the budget + off/on comparison are **documented** (`docs/BATTERY.md`). Absolute drain
/// is measured on the device matrix.
final class BatteryBaselineTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func strippedCode(of file: URL) throws -> String {
        let contents = try String(contentsOf: file, encoding: .utf8)
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

    private func swiftFiles(under module: String) -> [URL] {
        let directory = repoRoot().appendingPathComponent("Sources/\(module)")
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
    }

    func testLocationSensingIsLowPowerNoContinuousDrain() throws {
        // Continuous-drain APIs that would blow the overnight budget. Only significant-location is allowed.
        let continuous = [
            "startUpdatingLocation", "allowsBackgroundLocationUpdates", "desiredAccuracy",
            "distanceFilter", "startMonitoringVisits", "startUpdatingHeading",
        ]
        let files = swiftFiles(under: "TravelInfrastructure")
        XCTAssertFalse(files.isEmpty)
        var usesSignificant = false
        for file in files {
            let code = try strippedCode(of: file)
            if code.contains("startMonitoringSignificantLocationChanges") { usesSignificant = true }
            for api in continuous {
                XCTAssertFalse(
                    code.contains(api),
                    "\(file.lastPathComponent) uses continuous-drain API '\(api)' — overnight battery"
                )
            }
        }
        XCTAssertTrue(
            usesSignificant, "travel detection must use low-power significant-location changes")
    }

    func testHealthKitIsNotContinuouslyObserved() throws {
        // Continuous-observation / background-delivery APIs would turn nightly sleep reads into a real-time
        // wake trigger — violating the core constraint and the +health battery budget. Only on-demand
        // one-shot queries are allowed; sleep is never observed live (WG-249).
        let continuous = ["HKObserverQuery", "HKAnchoredObjectQuery", "enableBackgroundDelivery"]
        let files = swiftFiles(under: "HealthInfrastructure")
        XCTAssertFalse(files.isEmpty)
        var usesOnDemandQuery = false
        for file in files {
            let code = try strippedCode(of: file)
            if code.contains("HKSampleQuery") { usesOnDemandQuery = true }
            for api in continuous {
                XCTAssertFalse(
                    code.contains(api),
                    "\(file.lastPathComponent) uses continuous HealthKit API '\(api)' — sleep must "
                        + "not be a real-time trigger")
            }
        }
        XCTAssertTrue(
            usesOnDemandQuery, "sleep must be read on demand via HKSampleQuery, never observed live"
        )
    }

    func testBatteryBudgetAndOffOnComparisonAreDocumented() throws {
        let doc = try String(
            contentsOf: repoRoot().appendingPathComponent("docs/BATTERY.md"), encoding: .utf8)
        for required in ["Budget", "off vs on", "regression", "device conditions"] {
            XCTAssertTrue(
                doc.lowercased().contains(required.lowercased()),
                "battery doc missing '\(required)'")
        }
    }
}
