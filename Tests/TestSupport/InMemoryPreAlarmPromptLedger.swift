import Foundation

@testable import WakeGuard

/// An in-memory `PreAlarmPromptLedger` for tests (WG-089): an atomic, `Set`-backed idempotency claim.
/// An `actor`, so the check-and-mark is race-free like the persisted ledger.
actor InMemoryPreAlarmPromptLedger: PreAlarmPromptLedger {
    private var claimed: Set<String> = []

    func claim(_ key: PreAlarmPromptKey, at now: Date) async -> Bool {
        claimed.insert(key.identifier).inserted
    }

    /// Test inspection: how many distinct prompts have been claimed.
    var count: Int { claimed.count }
}
