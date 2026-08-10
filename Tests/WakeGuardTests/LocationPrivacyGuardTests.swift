import Foundation
import XCTest

/// WG-109 privacy guard. The education copy (`LocationEducation`) *promises* "low-power
/// significant-location changes … never continuous GPS", "never records where you are", and that
/// time-zone detection "keeps your alarms working even if you never grant location access". These
/// source-scanning tests **lock those promises** against future edits: if someone adds a continuous-GPS /
/// high-precision API, spreads Core Location beyond the one WG-102 adapter, or couples time-zone
/// detection to location, a test fails and the copy stops being true. Static guards — they read the
/// checked-in `Sources/` via `#filePath`; comment lines are stripped so a doc mention isn't a false hit.
final class LocationPrivacyGuardTests: XCTestCase {

    private func sourcesDirectory() -> URL {
        // …/damascus/Tests/WakeGuardTests/<thisFile> → repo root → Sources
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    /// The file's contents with comment lines and inline `//` comments removed, so a token named only in
    /// documentation (e.g. "`startUpdatingLocation` is never called") is not mistaken for a real use.
    private func code(of file: URL) throws -> String {
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

    private func swiftFiles(under directory: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
    }

    func testTravelInfrastructureUsesNoContinuousOrHighPrecisionLocationAPI() throws {
        // The APIs the "never continuous GPS" copy rules out. Only the low-power
        // `startMonitoringSignificantLocationChanges` is permitted (WG-102).
        let forbidden = [
            "startUpdatingLocation", "requestLocation", "startMonitoringVisits",
            "allowsBackgroundLocationUpdates", "desiredAccuracy", "distanceFilter",
        ]
        let directory = sourcesDirectory().appendingPathComponent("TravelInfrastructure")
        let files = swiftFiles(under: directory)
        XCTAssertFalse(files.isEmpty, "expected TravelInfrastructure sources at \(directory.path)")
        for file in files {
            let source = try code(of: file)
            for token in forbidden {
                XCTAssertFalse(
                    source.contains(token),
                    "\(file.lastPathComponent) uses \(token) — WG-109's 'never continuous GPS' copy "
                        + "would be false")
            }
        }
    }

    func testTimeZoneDetectionHasNoLocationDependency() throws {
        // Claim: time-zone travel detection works without location — it must not touch Core Location or
        // the significant-location source.
        let root = sourcesDirectory()
        let files = [
            root.appendingPathComponent("TravelDomain/TimeZoneChange.swift"),
            root.appendingPathComponent("TravelInfrastructure/SystemTimeZoneMonitor.swift"),
        ]
        for file in files {
            let source = try code(of: file)
            XCTAssertFalse(
                source.contains("CoreLocation"), "\(file.lastPathComponent) imports CoreLocation")
            XCTAssertFalse(
                source.contains("SignificantLocation"),
                "\(file.lastPathComponent) references the location source")
        }
    }

    func testCoreLocationIsConfinedToTheOneWG102Adapter() throws {
        let importers =
            swiftFiles(under: sourcesDirectory())
            .filter { (try? code(of: $0))?.contains("import CoreLocation") ?? false }
            .map(\.lastPathComponent).sorted()
        XCTAssertEqual(
            importers, ["CoreLocationSignificantLocationAdapter.swift"],
            "Core Location must stay confined to the one WG-102 adapter — a new importer means the "
                + "location privacy surface must be re-audited")
    }
}
