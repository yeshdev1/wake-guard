import Foundation

/// Sample alarm data a reviewer/preview build may seed (WG-191). These are **ordinary alarm definitions**
/// — real data the normal create flow could produce — **not** simulated behavior or fake capabilities. A
/// demo build loads them so the reviewer sees a populated UI without hand-entering alarms first.
enum ReviewDemoContent {
    /// A minimal, real alarm definition (label + time + weekly days + criticality).
    struct SampleAlarm: Sendable, Equatable, Hashable {
        let label: String
        let hour: Int
        let minute: Int
        let weekdays: Set<Weekday>
        let isCritical: Bool
    }

    static let sampleAlarms: [SampleAlarm] = [
        SampleAlarm(
            label: "Wake up", hour: 7, minute: 0,
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday], isCritical: false),
        SampleAlarm(
            label: "Weekend lie-in", hour: 9, minute: 0, weekdays: [.saturday, .sunday],
            isCritical: false),
        // One critical example so a reviewer can see the confirmation behavior; the user sets criticality,
        // never the app or the AI.
        SampleAlarm(
            label: "Important: catch flight", hour: 5, minute: 30, weekdays: Set(Weekday.allCases),
            isCritical: true),
    ]
}
