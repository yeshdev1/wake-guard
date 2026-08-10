import Foundation

/// A framework-independent, per-type health authorization status (WG-121). The HealthKit
/// `HKAuthorizationStatus` is mapped at the adapter boundary. **Read caveat:** HealthKit deliberately does
/// not reveal *read* authorization (to avoid leaking whether data exists), so a real adapter reports
/// `.authorized` once the user has been asked; genuine readability is confirmed by whether a query returns
/// data (WG-122), never by this status. `.denied`/`.restricted` still occur (a restricted/parental
/// environment), and the domain models them so they're handled, fail-closed.
enum HealthAuthorizationStatus: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// The coarse outcome of requesting read access to the plan's types (WG-121). Distinguishes device
/// **unavailability**, a **full** grant, a **partial** grant (some types authorized, some not), and
/// **denial** — so the readiness feature can use exactly the subset it's allowed while the rest of the app
/// is unaffected. The app **remains functional** in every case; only the optional readiness feature
/// depends on this.
enum HealthAccessSummary: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case unavailable
    case notDetermined
    case granted
    case partial
    case denied

    /// Fold the counts of requested vs authorized read types into a coarse summary. `anyDenied`
    /// distinguishes "declined / restricted" from "not yet asked" when nothing is authorized. Modelled on
    /// counts so **partial is supported and testable** even while only one type is requested today.
    static func of(requested: Int, authorized: Int, anyDenied: Bool) -> HealthAccessSummary {
        guard requested > 0 else { return .notDetermined }
        if authorized >= requested { return .granted }
        if authorized == 0 { return anyDenied ? .denied : .notDetermined }
        return .partial
    }
}

/// Port for HealthKit authorization (WG-121). The real adapter (device-only, `HealthInfrastructure`) maps
/// HealthKit; the domain stays framework-independent. Only **read** access is ever requested.
protocol HealthAuthorizationProviding: Sendable {
    func isHealthDataAvailable() async -> Bool
    /// Request **read** access to exactly `types`, returning the per-type status the system reveals.
    func requestReadAccess(to types: Set<WellnessHealthType>) async
        -> [WellnessHealthType: HealthAuthorizationStatus]
}

/// Contextual HealthKit authorization (WG-121). Requests **only** the read types in the
/// data-minimization plan (WG-120) — never more — and folds the result into a coarse `HealthAccessSummary`
/// that supports denied and partial access. Holds no alarm authority; the app's core (alarms, travel) is
/// **independent of health**, so it remains functional in every authorization state.
struct HealthAuthorizationCoordinator: Sendable {
    let plan: WellnessDataMinimizationPlan
    let provider: any HealthAuthorizationProviding

    init(plan: WellnessDataMinimizationPlan = .mvp, provider: any HealthAuthorizationProviding) {
        self.plan = plan
        self.provider = provider
    }

    /// The types the app will request — **exactly** the plan's (only necessary read types).
    var requestedTypes: Set<WellnessHealthType> { Set(plan.requestedTypes) }

    /// Request read access in context, returning a coarse summary. `unavailable` when HealthKit is absent
    /// on the device — no request is made.
    func requestAccess() async -> HealthAccessSummary {
        guard await provider.isHealthDataAvailable() else { return .unavailable }
        let requested = requestedTypes
        let statuses = await provider.requestReadAccess(to: requested)
        let authorized = requested.filter { statuses[$0] == .authorized }.count
        let anyDenied = requested.contains {
            let status = statuses[$0] ?? .notDetermined
            return status == .denied || status == .restricted
        }
        return .of(requested: requested.count, authorized: authorized, anyDenied: anyDenied)
    }

    /// Whether the readiness feature may proceed (for its authorized subset) — only when at least
    /// partially granted. Every other state degrades the **optional** feature to unavailable; it **never**
    /// affects alarms or travel (#36/#38).
    func isReadinessAvailable(_ summary: HealthAccessSummary) -> Bool {
        summary == .granted || summary == .partial
    }
}
