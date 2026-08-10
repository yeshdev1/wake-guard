import Foundation

/// A HealthKit data type WakeGuard may read, named in a **framework-independent** way so the domain stays
/// Foundation-only — the HealthKit `HKObjectType` mapping happens at the adapter boundary (WG-121). The
/// MVP reads sleep only; readiness (WG-125) is derived from that sleep data, not from extra signals.
enum WellnessHealthType: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case sleepAnalysis
}

/// The access WakeGuard requests for a wellness type. **`read` is the only value** — WakeGuard never
/// writes to HealthKit, so the plan cannot express a write.
enum WellnessAccessMode: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case read
}

/// Where a wellness data type may be processed. **`onDeviceOnly` is the only permitted value** — the plan
/// literally cannot express cloud processing, so raw HealthKit can never be sent to a cloud model by
/// default (#35, ADR-004). Cloud analysis, if ever offered, is a separate opt-in consent (#34), never a
/// value here.
enum ProcessingLocality: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case onDeviceOnly
}

/// How long raw samples of a type are kept. **`computeAndDiscard`** — raw HealthKit samples are read,
/// used to compute a derived estimate, and **not retained**; only coarse derived aggregates persist,
/// under explicit/configurable retention and the export/delete controls (WG-129) (#42/#43).
enum WellnessRetention: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case computeAndDiscard
}

/// One entry in the wellness data-minimization plan (WG-120): a requested HealthKit type plus its
/// **user-facing purpose**, access mode, raw-sample retention, and processing locality.
struct WellnessDataMinimizationEntry: Sendable, Equatable, Hashable, Codable {
    let type: WellnessHealthType
    /// Plain-language reason the type is read — shown to the user in context (WG-121). Never a medical
    /// claim (#39): a sleep *estimate*, not a diagnosis.
    let userFacingPurpose: String
    let access: WellnessAccessMode
    let retention: WellnessRetention
    let processing: ProcessingLocality

    /// Cloud exclusion is **structural**: the only processing locality is on-device (#35). Exposed so the
    /// guarantee is explicit and testable, not merely implied.
    var isCloudExcluded: Bool { processing == .onDeviceOnly }
}

/// The wellness data-minimization plan (WG-120): the **complete, minimal** set of HealthKit types
/// WakeGuard may read, each with a user-facing purpose, read-only access, on-device-only processing,
/// compute-and-discard raw retention, and structural cloud exclusion. It is the **single source of truth**
/// contextual authorization (WG-121) consumes — the app requests **exactly** these types, nothing more.
/// Adding a type is a deliberate change here (new entry + purpose + re-consent), never ad hoc at a call
/// site.
struct WellnessDataMinimizationPlan: Sendable, Equatable, Codable {
    let entries: [WellnessDataMinimizationEntry]

    static let mvp = WellnessDataMinimizationPlan(entries: [
        WellnessDataMinimizationEntry(
            type: .sleepAnalysis,
            userFacingPurpose:
                "Estimate your recent sleep duration and consistency to explain your morning readiness. "
                + "This is a sleep estimate, never a diagnosis.",
            access: .read, retention: .computeAndDiscard, processing: .onDeviceOnly)
    ])

    func entry(for type: WellnessHealthType) -> WellnessDataMinimizationEntry? {
        entries.first { $0.type == type }
    }

    /// The types the app is permitted to request — exactly the plan's entries (data minimization: nothing
    /// is requested without a documented purpose here).
    var requestedTypes: [WellnessHealthType] { entries.map(\.type) }
}
