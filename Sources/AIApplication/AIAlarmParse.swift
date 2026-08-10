import Foundation

/// The model's structured reading of a natural-language alarm request (WG-164). It deliberately records
/// *what the user did not say* — whether a time was given at all (`timeSpecified`) and whether AM/PM was
/// stated (`meridiemSpecified`) — so the **deterministic** parser can offer **bounded clarification
/// choices** instead of guessing. It carries **no criticality** (#31) and no alarm command: it is inert
/// extraction that the deterministic layer (WG-164) and validator (WG-165) interpret.
struct AIAlarmParse: Sendable, Equatable, Hashable, Codable {
    /// The stated hour. When `meridiemSpecified` is `false` this is the 1–12 clock hour the user said
    /// ("at 8" ⇒ 8); when `true` it is the resolved 0–23 hour.
    let hour: Int
    let minute: Int
    /// `false` ⇒ the user did not say AM/PM and did not use 24-hour time ("at 8") ⇒ ambiguous.
    let meridiemSpecified: Bool
    /// `false` ⇒ the user gave no time at all ⇒ we must ask, never guess.
    let timeSpecified: Bool
    /// Days a repeating alarm fires; empty ⇒ a one-time alarm.
    let weekdays: Set<AIWeekday>
    /// Days from today for a one-time alarm (0 = today, 1 = tomorrow); `nil` if unspecified or weekly.
    let dayOffset: Int?

    func validate() throws {
        guard (0...23).contains(hour) else { throw AISchemaError.outOfRange(field: "hour") }
        guard (0...59).contains(minute) else { throw AISchemaError.outOfRange(field: "minute") }
    }
}
