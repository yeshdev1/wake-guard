import Foundation

@testable import WakeGuard

/// An in-memory `PreAlarmNotificationScheduling` for tests: records registrations, posts, and cancels
/// so the response runtime can be exercised without UserNotifications. Thread-safe (reference type).
final class InMemoryPreAlarmNotificationScheduler: PreAlarmNotificationScheduling {
    struct Post: Sendable, Equatable {
        let context: PreAlarmResponseContext
        let date: Date
    }

    private struct State: Sendable {
        var registeredCount = 0
        var posts: [Post] = []
        var cancels: [AlarmID] = []
    }

    private let state = Synchronized(State())

    var registeredCount: Int { state.get().registeredCount }
    var posts: [Post] { state.get().posts }
    var cancels: [AlarmID] { state.get().cancels }

    func registerPromptCategory() async {
        state.mutate { $0.registeredCount += 1 }
    }

    func postPrompt(_ context: PreAlarmResponseContext, at date: Date) async {
        state.mutate { $0.posts.append(Post(context: context, date: date)) }
    }

    func cancelPrompt(alarmID: AlarmID, occurrence: Date) async {
        state.mutate { $0.cancels.append(alarmID) }
    }
}
