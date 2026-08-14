import Foundation

/// A coarse, **app-derived** wellness aggregate (WG-129) — WakeGuard's OWN on-device estimate, not a raw
/// HealthKit sample (those are compute-and-discard, WG-120) and not the Apple Health source. This is the
/// only wellness data WakeGuard stores, so it is the only thing export/delete acts on.
struct DerivedWellnessRecord: Sendable, Equatable, Hashable, Codable {
    let date: Date
    let asleepDuration: TimeInterval?
}

/// Who performed a wellness deletion (WG-129). Only the user resets their own data.
enum WellnessDeletionActor: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case user
}

/// The audit record of a deletion (WG-129): records **that** a deletion happened — actor, count, when —
/// and deliberately **no deleted content** (#41/#46). There is no field that could hold a sleep value.
struct WellnessDeletionReceipt: Sendable, Equatable, Hashable, Codable {
    let deletedAt: Date
    let recordCount: Int
    let actor: WellnessDeletionActor
}

/// A full local export of WakeGuard's derived wellness data (WG-129), with explicit **provenance**: the
/// export is the app's own on-device estimates, **not** the Apple Health source (that stays in Health,
/// owned by the user), and deleting in WakeGuard changes nothing in Apple Health.
struct WellnessExportPayload: Sendable, Equatable, Codable {
    let exportedAt: Date
    let provenance: String
    let records: [DerivedWellnessRecord]

    static let provenanceNote =
        "These are Alarm Agent's own on-device estimates derived from your sleep data. They are not your "
        + "Apple Health records — that data stays in Apple Health, owned by you. Deleting data in "
        + "Alarm Agent does not change anything in Apple Health."
}

/// The app's local derived-wellness store (WG-129). The concrete Core Data implementation is a
/// persistence follow-on; the controls act through this port. It holds **only** derived aggregates —
/// never raw HealthKit samples.
protocol DerivedWellnessStore: Sendable {
    func records() async throws -> [DerivedWellnessRecord]
    /// Delete all derived records; returns how many were deleted.
    func deleteAll() async throws -> Int
}

/// Append-only audit sink for wellness deletions (WG-129) — receives a content-free `WellnessDeletionReceipt`.
protocol WellnessDeletionAuditing: Sendable {
    func record(_ receipt: WellnessDeletionReceipt) async throws
}

/// Export and delete controls for the user's **derived** wellness data (WG-129, #42). Export includes
/// provenance disclaiming ownership of the HealthKit source; delete removes the local derived data and
/// audits the deletion **without retaining its content**.
struct WellnessDataControls: Sendable {
    let store: any DerivedWellnessStore
    let audit: any WellnessDeletionAuditing

    /// A full local export of the derived estimates, with provenance. Contains only the app's derived
    /// aggregates — never the Apple Health source.
    func export(now: Date) async throws -> WellnessExportPayload {
        WellnessExportPayload(
            exportedAt: now, provenance: WellnessExportPayload.provenanceNote,
            records: try await store.records())
    }

    /// Delete all local derived wellness data and audit the deletion **without retaining its content**.
    /// Returns the content-free receipt. Does **not** touch Apple Health (WakeGuard doesn't own it).
    func deleteAllDerivedData(now: Date, actor: WellnessDeletionActor = .user) async throws
        -> WellnessDeletionReceipt
    {
        let count = try await store.deleteAll()
        let receipt = WellnessDeletionReceipt(deletedAt: now, recordCount: count, actor: actor)
        try await audit.record(receipt)
        return receipt
    }
}
