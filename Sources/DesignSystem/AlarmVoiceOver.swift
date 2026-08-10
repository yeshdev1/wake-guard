import Foundation

/// A destructive action whose **consequence must be spoken** before the user commits (WG-201). VoiceOver
/// users need the outcome announced, not just a button label.
enum DestructiveAction: String, Sendable, Equatable, Hashable, CaseIterable {
    case cancelAlarm
    case deleteAllData
    case deleteOptionalData
    case disableCriticalAlarm
}

/// VoiceOver copy for alarm status and destructive consequences (WG-201). Domain-independent strings so the
/// **alarm status and destructive consequences are announced** — a screen-reader user hears the current
/// state and the exact outcome of a destructive tap, never a bare "button".
enum AlarmVoiceOver {
    /// The announcement for the current alarm status — the status label plus, when scheduled, the next ring
    /// time — so the state is understandable eyes-free.
    static func statusAnnouncement(_ style: AlarmStatusStyle, nextRing: String?) -> String {
        guard let nextRing else { return style.label }
        return "\(style.label). Next alarm at \(nextRing)."
    }

    /// The spoken consequence of a destructive action, announced before confirmation. Alarm-affecting
    /// actions always say whether an alarm will still ring.
    static func consequence(of action: DestructiveAction) -> String {
        switch action {
        case .cancelAlarm:
            "Cancels this alarm. It will not ring."
        case .deleteAllData:
            "Deletes all app data and cancels your scheduled alarms. They will not ring. This can’t be "
                + "undone."
        case .deleteOptionalData:
            "Deletes the selected data. Your alarms are unaffected and still ring."
        case .disableCriticalAlarm:
            "Turns off a critical alarm. It will no longer ring through silent mode or Focus."
        }
    }
}
