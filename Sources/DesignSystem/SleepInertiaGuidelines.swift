import Foundation

/// Design guidelines for **sleep-inertia-safe** wake screens (WG-208). A groggy, just-woken user needs
/// **minimal choices**, **short** copy, and **no** way to destroy state with a single stray tap. These
/// bounds are enforced against the ringing/challenge screens by tests.
enum SleepInertiaGuidelines {
    /// The most interactive controls a wake/challenge screen may show.
    static let maxWakeScreenActions = 3

    /// The longest a single piece of on-screen copy on a wake screen should be — short and concrete.
    static let maxWakeCopyCharacters = 48
}
