import Foundation
import Observation

/// Drives the local-data export (WG-183). On an explicit user action it collects the export categories,
/// builds a **versioned, labeled** bundle, and writes it to a temporary file for the **system share
/// sheet** — it never transmits anything itself. Holds no alarm authority.
@MainActor
@Observable
final class DataExportModel {
    private(set) var export: ShareableExport?
    /// The temp file to hand to `ShareLink`; set once an export is prepared.
    private(set) var fileURL: URL?
    private(set) var didFail = false

    private let categories: @Sendable () async -> [ExportCategory]
    private let clock: any WallClock

    init(clock: any WallClock, categories: @escaping @Sendable () async -> [ExportCategory]) {
        self.clock = clock
        self.categories = categories
    }

    /// Prepare the export (user-initiated). Total and non-throwing — a failure sets `didFail`, never
    /// crashes, and nothing is shared automatically.
    func prepareExport() async {
        do {
            let shareable = try ExportBuilder.shareable(
                categories: await categories(), exportedAt: clock.now)
            export = shareable
            fileURL = try shareable.writeToTemporaryFile()
            didFail = false
        } catch {
            export = nil
            fileURL = nil
            didFail = true
        }
    }
}
