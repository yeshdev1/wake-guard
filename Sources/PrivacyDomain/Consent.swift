import Foundation

/// A permission / data category the user consents to **separately** (WG-180). Each is independent — the
/// app stays functional when any optional one is denied, and the two core ones (alarm, notifications)
/// are what an alarm needs.
enum ConsentCategory: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case alarm
    case notifications
    case motion
    case location
    case health
    case calendar
    case cloudAI
}

/// The coarse, framework-independent status of a consent category (WG-180). Adapters map the OS
/// authorization onto this; `.unavailable` covers hardware/OS that can't provide the capability.
enum ConsentStatus: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case granted
    case denied
    case notDetermined
    case restricted
    case unavailable
}

/// The static, user-facing description of a consent category (WG-180): its purpose and **revocation
/// guidance**. Honest and matched to app behavior — never a medical or advertising claim.
struct ConsentCategoryInfo: Sendable, Equatable, Hashable {
    let category: ConsentCategory
    let title: String
    let purpose: String
    let revocationGuidance: String
    /// `false` for the two categories an alarm needs (alarm, notifications); `true` for optional data.
    let isOptional: Bool
}

/// The copy for the permission & consent center (WG-180). One honest entry per category — purpose plus how
/// to revoke — so the user always sees *why* each capability is used and *how* to turn it off.
enum ConsentCopy {
    static func info(for category: ConsentCategory) -> ConsentCategoryInfo {
        switch category {
        case .alarm: alarm
        case .notifications: notifications
        case .motion: motion
        case .location: location
        case .health: health
        case .calendar: calendar
        case .cloudAI: cloudAI
        }
    }

    static var allInfo: [ConsentCategoryInfo] { ConsentCategory.allCases.map(info(for:)) }

    private static let alarm = ConsentCategoryInfo(
        category: .alarm, title: "Alarms",
        purpose:
            "Schedules and rings your alarms, including critical alarms that sound through silent mode "
            + "and Focus.",
        revocationGuidance: "Alarms need this. Manage it in Settings › Alarm Agent.",
        isOptional: false)

    private static let notifications = ConsentCategoryInfo(
        category: .notifications, title: "Notifications",
        purpose: "Shows pre-alarm prompts and alarm notifications.",
        revocationGuidance:
            "Turn off in Settings › Notifications › Alarm Agent. Your scheduled alarms still ring.",
        isOptional: false)

    private static let motion = ConsentCategoryInfo(
        category: .motion, title: "Motion & Fitness",
        purpose: "Powers the optional walk challenge and pre-alarm movement check, on device only.",
        revocationGuidance:
            "Turn off in Settings › Privacy › Motion & Fitness. The walk challenge has an accessible "
            + "alternative.", isOptional: true)

    private static let location = ConsentCategoryInfo(
        category: .location, title: "Location",
        purpose:
            "Detects travel and time-zone changes using low-power significant-location changes — never "
            + "continuous GPS, never a stored location.",
        revocationGuidance:
            "Turn off in Settings › Privacy › Location Services. Alarms and time-zone detection still "
            + "work.", isOptional: true)

    private static let health = ConsentCategoryInfo(
        category: .health, title: "Health (Sleep)",
        purpose:
            "Estimates sleep readiness from sleep data, on device only. It is an estimate, never a "
            + "diagnosis.",
        revocationGuidance:
            "Turn off in Settings › Privacy › Health › Alarm Agent. The rest of the app is unaffected.",
        isOptional: true)

    private static let calendar = ConsentCategoryInfo(
        category: .calendar, title: "Calendar",
        purpose:
            "Suggests a safe wake time from your earliest event. Only event times are read — never "
            + "titles, notes, or locations.",
        revocationGuidance:
            "Turn off in Settings › Privacy › Calendars. Your alarms are unaffected.",
        isOptional: true)

    private static let cloudAI = ConsentCategoryInfo(
        category: .cloudAI, title: "Cloud AI",
        purpose:
            "Off by default. AI runs on device. If you enable cloud AI with separate consent, only "
            + "minimized, redacted data is sent.",
        revocationGuidance:
            "Turn off any time in Alarm Agent Settings. On-device AI and alarms are unaffected.",
        isOptional: true)
}

/// A category's current state for the consent center (WG-180): its static info + live status.
struct ConsentCategoryState: Sendable, Equatable, Hashable {
    let info: ConsentCategoryInfo
    let status: ConsentStatus
}

/// Reports the current status of each consent category (WG-180). The composition root implements this by
/// mapping each OS authorization / setting; the domain stays framework-independent so it is testable and
/// carries no alarm authority.
protocol ConsentStatusProviding: Sendable {
    func status(for category: ConsentCategory) async -> ConsentStatus
}
