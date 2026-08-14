import AppIntents
import Foundation
import Observation

/// A shared, in-process inbox the alarm's "Start walk" intent writes and the app reads to present the walk
/// challenge for the alerting alarm (WG-282). The intent opens the app and runs in its process, so the value
/// is visible to the running app; `RootView` observes it and presents the challenge full-screen, then clears
/// it on dismiss. Purely navigational — it never stops or mutates an alarm.
@MainActor @Observable
final class WakeChallengeLaunchInbox {
    static let shared = WakeChallengeLaunchInbox()
    private init() {}

    /// The alarm whose walk challenge should be presented, or nil once handled / dismissed.
    private(set) var requestedAlarmID: UUID?

    /// Called from the alarm's "Start walk" intent. A malformed id is ignored (fail-safe — never a crash).
    func request(alarmID: String) { requestedAlarmID = UUID(uuidString: alarmID) }

    func clear() { requestedAlarmID = nil }
}

/// The App Intent behind a challenge alarm's **"Start walk"** button (WG-281/282). Tapping it opens the app
/// and requests the walk challenge for the alarm — it does **not** stop the alarm; only a genuine challenge
/// pass does (WG-073). The mandatory system Stop button remains the escape hatch (AlarmKit requires it).
struct OpenWakeChallengeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start walk"
    static let openAppWhenRun = true

    @Parameter(title: "Alarm") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    @MainActor
    func perform() async throws -> some IntentResult {
        WakeChallengeLaunchInbox.shared.request(alarmID: alarmID)
        return .result()
    }
}
