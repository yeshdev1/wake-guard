import Foundation

/// Decides whether to actually surface a pre-alarm prompt (WG-089) — the de-dup between the background
/// opportunity (WG-088) and the foreground fallback. Given a WG-082 recommendation for a specific
/// occurrence, it surfaces **at most once per (alarm, occurrence)** via the ledger's idempotency
/// claim: whichever path (background or app launch) claims the key first surfaces the prompt; the
/// other suppresses. It holds **no alarm authority** — the recommendation carries none, and this
/// coordinator only reads the ledger, so the original alarm is never changed and stays clearly
/// scheduled (#7/#8).
struct PreAlarmPromptCoordinator: Sendable {
    let ledger: any PreAlarmPromptLedger

    /// Whether to surface the prompt now. `true` only when the recommendation prompts **and** this
    /// occurrence's key hasn't already been surfaced. A declined recommendation does **not** claim the
    /// key, so a later evaluation that does recommend prompting can still surface it once.
    func surface(
        _ recommendation: PreAlarmRecommendation, for key: PreAlarmPromptKey, at now: Date
    ) async -> Bool {
        guard recommendation.shouldPrompt else { return false }
        return await ledger.claim(key, at: now)
    }
}
