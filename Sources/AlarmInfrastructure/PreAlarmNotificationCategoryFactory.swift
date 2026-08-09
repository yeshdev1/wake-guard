import UserNotifications

/// Maps the pure `PreAlarmPromptContent` (WG-083) to the real `UNNotificationCategory` +
/// `UNNotificationAction`s iOS registers for the pre-alarm prompt. This is the only place that
/// touches `UserNotifications`; the actions, order, destructive/confirmation semantics, and copy are
/// all decided in the Foundation-only domain model and merely translated here.
///
/// Not unit-tested — `UNNotificationCategory` is a system type best verified on a device (see the
/// WG-083 real-device checklist). The mapping is intentionally thin and total; the tested logic
/// (which buttons, in what order, with which flags, and the #7 warning copy) lives in `AlarmApplication`.
enum PreAlarmNotificationCategoryFactory {

    /// The registered category for the prompt.
    static func category(for content: PreAlarmPromptContent) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: PreAlarmPromptContent.categoryIdentifier,
            actions: content.buttons.map(action(for:)),
            intentIdentifiers: [], options: [])
    }

    private static func action(for button: PreAlarmPromptButton) -> UNNotificationAction {
        var options: UNNotificationActionOptions = []
        // A destructive change renders distinctly (red); a critical alarm's destructive action also
        // demands the device be **unlocked** — a lock gate, NOT the #6 explicit confirmation. The real
        // confirmation + the mutation are gated by AlarmCommandProcessor when the app handles the
        // response (an unconfirmed critical change returns `.needsConfirmation`). A critical
        // `turnOffToday` is not `.foreground`, so that handler (WG-085) must foreground to collect the
        // real confirmation — never treat "unlocked" as "confirmed".
        if button.isDestructive { options.insert(.destructive) }
        if button.requiresConfirmation { options.insert(.authenticationRequired) }
        if button.opensApp { options.insert(.foreground) }
        return UNNotificationAction(
            identifier: button.action.identifier, title: title(button.titleKey), options: options)
    }

    /// Resolve a button title, localization-ready — the development-language value is the fallback
    /// until E11 ships translated `.strings`.
    private static func title(_ key: String) -> String {
        NSLocalizedString(
            key, value: PreAlarmPromptStrings.developmentFallback(for: key),
            comment: "Pre-alarm prompt action title")
    }
}
