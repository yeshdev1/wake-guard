import Foundation

/// The smart-pre-alarm form state for the create/edit alarm flow (WG-047). Holds whether the
/// pre-alarm is enabled, its bounded lead-time window, and the actions the prompt may offer, and
/// builds a validated `PreAlarmPolicy`. The prompt's #7 guarantee (no response → the alarm rings
/// unchanged) and the critical-alarm confirmation limit are disclosed via `promptDisclosure`.
/// A value type stored on the `@Observable` view model, so the form binds to `preAlarm.*`.
struct PreAlarmDraft: Equatable, Sendable {
    var isEnabled: Bool = false
    var leadTimeMinutes: Int = Self.defaultLeadMinutes
    var allowedActions: Set<PreAlarmAction> = []

    static let defaultLeadMinutes = 30
    /// UI bounds for the lead-time window (minutes before the alarm). Every produced policy has
    /// `leadTime > 0`, the domain's own bound (`build()` clamps into this range).
    static let leadRange = 5...120

    init() {}

    /// Seed the form from an existing policy for editing.
    init(from policy: PreAlarmPolicy) {
        isEnabled = policy.isEnabled
        guard policy.isEnabled else { return }
        leadTimeMinutes = Self.clampMinutes(Int((policy.leadTime / 60).rounded()))
        allowedActions = policy.allowedActions
    }

    /// Build the validated policy. The lead time is clamped to the UI bounds, so
    /// `PreAlarmPolicy.enabled` never throws; a defensive `nil` (unreachable) degrades to
    /// `.disabled` rather than force-unwrapping.
    func build() -> PreAlarmPolicy {
        guard isEnabled else { return .disabled }
        let minutes = Self.clampMinutes(leadTimeMinutes)
        let policy = try? PreAlarmPolicy.enabled(
            leadTime: TimeInterval(minutes * 60), allowedActions: allowedActions)
        return policy ?? .disabled
    }

    /// The prompt disclosure (PRODUCT_SPEC §3.3 / #7): no response keeps the alarm, always; plus
    /// the informational-only note when no actions are offered, and the critical-alarm
    /// confirmation limit when the alarm is critical.
    static func promptDisclosure(isCritical: Bool, offersActions: Bool) -> String {
        var text = ""
        if !offersActions {
            text += "With no options selected, the prompt only lets you confirm you’re awake. "
        }
        text += "If you don’t respond, the alarm rings unchanged at its set time."
        if isCritical {
            text +=
                " Because this alarm is critical, turning it off or changing it from the prompt "
                + "needs confirmation — it’s never modified silently."
        }
        return text
    }

    private static func clampMinutes(_ value: Int) -> Int {
        let clamped = min(max(value, leadRange.lowerBound), leadRange.upperBound)
        // Align to the stepper's 5-minute step so an off-grid seed can't silently desync.
        return clamped / 5 * 5
    }
}
