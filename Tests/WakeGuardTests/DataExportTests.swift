import Foundation
import XCTest

@testable import WakeGuard

/// WG-183: full local export. Verifies the export **includes a schema version**, is **clearly labeled**,
/// round-trips through JSON, produces a dated file name for the **system share sheet**, and — as a pin of
/// *the export is never auto-transmitted* — that the builder references no network API.
final class DataExportTests: XCTestCase {

    private func date() throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        return try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11)))
    }

    private let categories = [
        ExportCategory(name: "alarms", records: [#"{"id":"a","hour":7}"#]),
        ExportCategory(name: "settings", records: [#"{"agentPermissionMode":"recommendOnly"}"#]),
    ]

    func testBundleIncludesSchemaVersion() throws {
        let bundle = ExportBuilder.bundle(categories: categories, exportedAt: try date())
        XCTAssertEqual(bundle.schemaVersion, ExportBundle.currentSchemaVersion)
        XCTAssertEqual(bundle.schemaVersion, 1)
    }

    func testBundleIsClearlyLabeled() throws {
        let bundle = ExportBuilder.bundle(categories: categories, exportedAt: try date())
        XCTAssertFalse(bundle.label.isEmpty)
        XCTAssertEqual(bundle.label, "WakeGuard data export")
    }

    func testEncodedExportRoundTripsAndCarriesTheVersion() throws {
        let bundle = ExportBuilder.bundle(categories: categories, exportedAt: try date())
        let data = try ExportBuilder.encode(bundle)
        let json = try XCTUnwrap(String(bytes: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"schemaVersion\""))
        let decoded = try ExportBuilder.decode(data)
        XCTAssertEqual(decoded, bundle)
    }

    func testShareableHasADatedJSONFileName() throws {
        let shareable = try ExportBuilder.shareable(categories: categories, exportedAt: try date())
        XCTAssertEqual(shareable.suggestedFileName, "WakeGuard-export-2026-08-11.json")
        XCTAssertFalse(shareable.data.isEmpty)
    }

    func testExportBuilderReferencesNoNetworkAPI() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PrivacyDomain/DataExport.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)
        for sink in ["URLSession", "URLRequest", "dataTask", "URL(string:"] {
            XCTAssertFalse(contents.contains(sink), "export must never auto-transmit: '\(sink)'")
        }
    }

    @MainActor
    func testViewModelPreparesAnExportOnUserAction() async throws {
        let exported = categories
        let model = DataExportModel(clock: TestClock(now: try date()), categories: { exported })
        await model.prepareExport()

        let export = try XCTUnwrap(model.export)
        XCTAssertFalse(export.data.isEmpty)
        XCTAssertNotNil(model.fileURL)
        XCTAssertFalse(model.didFail)
        let decoded = try ExportBuilder.decode(export.data)
        XCTAssertEqual(decoded.categories, exported)
    }
}
