import Foundation

/// Gathers the user's local data into export categories for the data-export flow (WG-183/250). It reads the
/// real stores and serializes each record to JSON — alarms, the audit log, and settings, the categories
/// with a persistent store today. No network access; the model hands the encoded bundle to the system
/// share sheet, and the OS + the user decide where it goes.
struct ExportDataProvider: Sendable {
    let alarms: any AlarmRepository
    let audit: any AuditRepository
    let settings: any SettingsRepository

    func categories() async -> [ExportCategory] {
        var result: [ExportCategory] = []
        if let list = try? await alarms.allAlarms() {
            result.append(ExportCategory(name: "alarms", records: encodeEach(list)))
        }
        if let events = try? await audit.allEvents() {
            result.append(ExportCategory(name: "audit", records: encodeEach(events)))
        }
        if let appSettings = try? await settings.settings() {
            result.append(ExportCategory(name: "settings", records: encodeEach([appSettings])))
        }
        return result
    }

    private func encodeEach(_ items: [some Encodable]) -> [String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return items.compactMap { item in
            (try? encoder.encode(item)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }
}
