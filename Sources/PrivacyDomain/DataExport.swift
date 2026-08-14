import Foundation

/// One named category in a local-data export (WG-183) — e.g. `alarms`, `audit`, `settings`, `journal`.
/// `records` are the already-serialized items for that category.
struct ExportCategory: Codable, Sendable, Equatable, Hashable {
    let name: String
    let records: [String]
}

/// A **full local-data export** bundle (WG-183). It is **versioned** (`schemaVersion`) and **clearly
/// labeled** (`label` + `exportedAt`), produced only on an explicit user action, and handed to the
/// **system share sheet** — the OS and the user decide where it goes. Nothing here transmits data; there is
/// no network path.
struct ExportBundle: Codable, Sendable, Equatable, Hashable {
    /// Bumped whenever the export shape changes, so an importer can detect the version.
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let label: String
    let exportedAt: Date
    let categories: [ExportCategory]
}

/// A ready-to-share export (WG-183): the encoded bytes and a suggested, dated file name for the system
/// share sheet.
struct ShareableExport: Sendable, Equatable {
    let data: Data
    let suggestedFileName: String

    /// Write the export to a temporary file so a SwiftUI `ShareLink`/share sheet can offer it — a
    /// user-initiated action; the OS controls the destination.
    func writeToTemporaryFile() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            suggestedFileName)
        try data.write(to: url, options: .completeFileProtection)
        return url
    }
}

/// Builds a full local-data export (WG-183). Pure: it assembles a **versioned, labeled** bundle from the
/// already-collected category payloads and encodes it to JSON for the system share sheet. It performs **no
/// network access** — the export is never auto-transmitted.
enum ExportBuilder {
    static let label = "Alarm Agent data export"

    static func bundle(categories: [ExportCategory], exportedAt: Date) -> ExportBundle {
        ExportBundle(
            schemaVersion: ExportBundle.currentSchemaVersion, label: label, exportedAt: exportedAt,
            categories: categories)
    }

    static func encode(_ bundle: ExportBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    /// Decode an export bundle with the matching (ISO-8601) date strategy — for importers and tests.
    static func decode(_ data: Data) throws -> ExportBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportBundle.self, from: data)
    }

    /// The user-initiated export: bundle → encode → a dated file name for the share sheet.
    static func shareable(categories: [ExportCategory], exportedAt: Date) throws -> ShareableExport
    {
        let data = try encode(bundle(categories: categories, exportedAt: exportedAt))
        return ShareableExport(data: data, suggestedFileName: fileName(at: exportedAt))
    }

    private static func fileName(at date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let stamp = String(
            format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "Alarm-Agent-export-\(stamp).json"
    }
}
