import Foundation

/// Gathers the user's local data into export categories for the data-export flow (WG-183/250). It reads the
/// real stores and serializes each record to JSON — alarms, the audit log, and settings, the categories
/// with a persistent store today. The audit log streams its **already-stored JSON payloads** in batches
/// (WG-182 scaling) rather than loading the whole table and re-encoding it, so peak memory stays bounded for
/// a long log. No network access; the model hands the encoded bundle to the system share sheet, and the OS +
/// the user decide where it goes.
struct ExportDataProvider: Sendable {
    let persistence: PersistenceController
    let alarms: any AlarmRepository
    let settings: any SettingsRepository

    func categories() async -> [ExportCategory] {
        var result: [ExportCategory] = []
        if let list = try? await alarms.allAlarms() {
            result.append(ExportCategory(name: "alarms", records: encodeEach(list)))
        }
        if let payloads = try? await persistence.auditPayloadsJSON() {
            result.append(ExportCategory(name: "audit", records: payloads))
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
