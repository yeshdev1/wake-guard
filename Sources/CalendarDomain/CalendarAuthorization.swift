import Foundation

/// A framework-independent EventKit authorization status (WG-141). The `EKAuthorizationStatus` is mapped
/// at the adapter boundary. `writeOnly` (iOS 17+) can add events but **cannot read** them, so it is not
/// usable for wake planning (which needs to read event times).
enum CalendarAuthorizationStatus: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case notDetermined
    case restricted
    case denied
    case writeOnly
    case fullAccess
}

/// The coarse access state calendar planning acts on (WG-141): `granted` only with **full read** access;
/// everything else leaves the **optional** planning feature unavailable while the rest of the app is
/// unaffected. A denied state is **useful** — the app stays functional and can point the user to Settings.
enum CalendarAccessState: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case notDetermined
    case granted
    case denied

    init(status: CalendarAuthorizationStatus) {
        switch status {
        case .fullAccess: self = .granted
        case .notDetermined: self = .notDetermined
        // Denied, restricted, and write-only all mean "can't read events" for our purpose.
        case .denied, .restricted, .writeOnly: self = .denied
        }
    }
}

/// Port for EventKit authorization (WG-141). The real adapter (`CalendarInfrastructure`) maps EventKit;
/// the domain stays framework-independent. Only **full read** access is ever requested — never write.
protocol CalendarAuthorizationProviding: Sendable {
    func authorizationStatus() async -> CalendarAuthorizationStatus
    /// Request **full (read) access** to events.
    func requestFullAccess() async -> CalendarAuthorizationStatus
}

/// Contextual EventKit authorization (WG-141). **Full read access is requested only when the user enables
/// calendar planning** — `currentState()` never prompts (for rendering a banner); `requestAccessForPlanning()`
/// is the sole request path and is called only from the opt-in. Holds no alarm authority; the app's core
/// is independent of calendar access, so it stays functional in every state.
struct CalendarAuthorizationCoordinator: Sendable {
    let provider: any CalendarAuthorizationProviding

    /// The current access state **without prompting** — safe on appear / foreground.
    func currentState() async -> CalendarAccessState {
        CalendarAccessState(status: await provider.authorizationStatus())
    }

    /// Request full read access. Call this **only** when the user enables calendar planning, never
    /// automatically (so the system prompt is always user-initiated and in context).
    func requestAccessForPlanning() async -> CalendarAccessState {
        CalendarAccessState(status: await provider.requestFullAccess())
    }

    /// Planning may proceed only with **full access** granted; every other state degrades the optional
    /// feature and never affects alarms or travel.
    func isPlanningAvailable(_ state: CalendarAccessState) -> Bool { state == .granted }
}
