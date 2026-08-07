import Foundation

/// The shared **Motion & Fitness** authorization (CMMotionActivityManager and CMPedometer share
/// one app-wide grant). String-raw so an unknown value fails to decode rather than being silently
/// admitted (#27).
enum MotionAuthorizationStatus: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case notDetermined
    case authorized
    /// The user declined — recoverable in Settings. Corresponds to
    /// `MotionSourceAvailability.notAuthorized` at the per-source level.
    case denied
    case restricted
}

/// The Motion & Fitness authorization primitive (WG-061). A domain-owned port — the real
/// CoreMotion-backed authorizer lives in `MotionInfrastructure`; tests use `FakeMotionAuthorizer`.
protocol MotionAuthorizing: Sendable {
    /// The current status — a value, never a thrown error.
    func authorizationStatus() async -> MotionAuthorizationStatus
    /// Request authorization (shows the system dialog when not-determined). Call this **only after**
    /// the purpose explanation has been shown. A thrown / interrupted request leaves the status
    /// unknown; the flow treats that as "use the accessible alternative", never an assumed denial.
    func requestAuthorization() async throws -> MotionAuthorizationStatus
}

/// The next step for setting up the wake-up **walk** challenge, given Motion & Fitness
/// authorization (WG-061). A closed, `Equatable` outcome so the flow is deterministic and testable.
/// Every non-authorized outcome routes to the **accessible alternative** — a user is never trapped
/// awake by a permission they declined or a sensor they can't use (#21; SCOPE §2.3).
enum MotionChallengeAuthorizationStep: Sendable, Equatable {
    /// Not yet determined — show the specific purpose explanation, *then* request. The system
    /// Motion & Fitness dialog must never appear unexplained (acceptance: requested in context).
    case explainThenRequest
    /// Authorized — the walk challenge *may* use motion. Authorization is app-wide and does **not**
    /// imply the pedometer hardware is present: the challenge runtime (E04) must re-check the
    /// per-source `availability()` and fall back to the accessible alternative on `.notPresent` /
    /// `.temporarilyUnavailable` before committing the user to a walk.
    case useWalkChallenge
    /// Denied — recoverable in Settings. Use the accessible alternative now **and** offer a Settings
    /// link to re-enable motion later; never block the user on the declined permission.
    case useAccessibleAlternativeOfferSettings
    /// Restricted by policy / parental controls (a Settings link can't change it) — use the
    /// accessible alternative.
    case useAccessibleAlternative
}

/// Specific purpose copy shown *before* the Motion & Fitness request (acceptance: purpose copy is
/// specific). It states exactly what motion is used for, what it is **not** used for, and that an
/// alternative exists — so the request is never a bare, unexplained system prompt.
enum MotionChallengePurpose {
    static let explanation =
        "WakeGuard uses Motion & Fitness only to confirm you're up and moving for the wake-up "
        + "walk — your steps and movement while the alarm is going off, never your location, and "
        + "never your saved workouts or health records. Prefer not to? You can use a tap or "
        + "press-and-hold challenge instead."
}

/// Orchestrates the Motion & Fitness authorization for the walk challenge (WG-061) around the
/// `MotionAuthorizing` port. Pure decision logic — it reads/requests authorization and returns the
/// next step; it never touches alarms, motion samples, or persistence. The explanation-before-
/// request contract is upheld by routing `.notDetermined` through `.explainThenRequest`; whether the
/// explanation screen was actually shown is the permission-UI's contract (the flow can't observe a
/// screen), and opening Settings for a denial is likewise the UI's job — this flow only *decides*.
struct MotionChallengeAuthorizationCoordinator: Sendable {
    private let authorizer: any MotionAuthorizing

    init(authorizer: any MotionAuthorizing) {
        self.authorizer = authorizer
    }

    /// The step for the *current* status, **without prompting** — reading it never triggers the
    /// system dialog (a not-determined status routes through the explanation first).
    func currentStep() async -> MotionChallengeAuthorizationStep {
        step(for: await authorizer.authorizationStatus(), afterRequest: false)
    }

    /// Perform the system request — call only *after* showing the explanation. A thrown / interrupted
    /// request falls back to the accessible alternative, so an interrupted setup never traps the user
    /// (and never assumes a denial).
    func requestAfterExplanation() async -> MotionChallengeAuthorizationStep {
        do {
            return step(for: try await authorizer.requestAuthorization(), afterRequest: true)
        } catch {
            // Interrupted / unknown → the always-available alternative, never an assumed denial.
            // The status stays not-determined, so the permission UI can retry by re-invoking this;
            // an explicit "try again" affordance is deferred to that UI (permission-center handoff).
            return .useAccessibleAlternative
        }
    }

    private func step(
        for status: MotionAuthorizationStatus, afterRequest: Bool
    ) -> MotionChallengeAuthorizationStep {
        switch status {
        case .authorized: return .useWalkChallenge
        case .denied: return .useAccessibleAlternativeOfferSettings
        case .restricted: return .useAccessibleAlternative
        // Before a request → explain then request; a still-not-determined result *after* a request
        // is anomalous, so fall back to the always-available alternative rather than loop.
        case .notDetermined: return afterRequest ? .useAccessibleAlternative : .explainThenRequest
        }
    }
}
