import Foundation

/// An **optional** data category the user may delete on its own (WG-184). Deleting any of these **never**
/// touches scheduled alarms — the app keeps ringing.
enum OptionalDataCategory: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case derivedMotion
    case recommendations
    case journal
    case healthDerived
}

/// What a deletion request covers (WG-184): a chosen set of optional categories, or **all** app data (a
/// full reset that also removes scheduled alarms).
enum DeletableScope: Sendable, Equatable, Hashable {
    case optionalCategories(Set<OptionalDataCategory>)
    case allData
}

/// The result of a deletion request (WG-184).
enum DeletionOutcome: Sendable, Equatable, Hashable {
    case deleted
    /// A full reset was requested without confirming the scheduled-alarm consequence — **nothing was
    /// deleted**; the caller must confirm first.
    case needsAlarmConsequenceConfirmation
    case failed
}

/// The deterministic deletion policy (WG-184). Its safety rule: a scope that **affects scheduled alarms**
/// (a full reset) may proceed **only** with an explicit alarm-consequence confirmation — deleting optional
/// data never requires it and never touches alarms (#9).
struct DeletionPolicy: Sendable {
    /// A full reset removes scheduled alarms; deleting optional categories does not.
    func affectsScheduledAlarms(_ scope: DeletableScope) -> Bool {
        switch scope {
        case .optionalCategories: false
        case .allData: true
        }
    }

    /// Whether the request may proceed to erasure given the user's confirmation.
    func mayProceed(_ scope: DeletableScope, userConfirmedAlarmConsequences: Bool) -> Bool {
        !affectsScheduledAlarms(scope) || userConfirmedAlarmConsequences
    }
}

/// Erases local data (WG-184). The composition root implements this over the real stores; the domain stays
/// framework-independent so the delete flow is testable and the completeness of deletion can be asserted.
protocol DataEraser: Sendable {
    /// Erase exactly the given optional categories — never alarms.
    func eraseOptional(_ categories: Set<OptionalDataCategory>) async throws
    /// Erase **all** app data, including cancelling and removing scheduled alarms (a full reset).
    func eraseAllData() async throws
}

/// Coordinates a deletion request through the policy and the eraser (WG-184). A full reset is **never**
/// carried out without an explicit alarm-consequence confirmation; deleting optional categories proceeds
/// directly and leaves alarms untouched.
struct DeletionCoordinator: Sendable {
    private let eraser: any DataEraser
    private let policy: DeletionPolicy

    init(eraser: any DataEraser, policy: DeletionPolicy = DeletionPolicy()) {
        self.eraser = eraser
        self.policy = policy
    }

    func delete(
        _ scope: DeletableScope, userConfirmedAlarmConsequences: Bool
    ) async -> DeletionOutcome {
        guard
            policy.mayProceed(scope, userConfirmedAlarmConsequences: userConfirmedAlarmConsequences)
        else {
            return .needsAlarmConsequenceConfirmation
        }
        do {
            switch scope {
            case .optionalCategories(let categories):
                try await eraser.eraseOptional(categories)
            case .allData:
                try await eraser.eraseAllData()
            }
            return .deleted
        } catch {
            return .failed
        }
    }
}
