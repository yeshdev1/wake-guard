import SwiftUI

/// Resolves animations against the **Reduce Motion** setting (WG-203). A moving animation is removed when
/// Reduce Motion is on (a `nil` animation is an instant, non-animated state change); an opacity cross-fade
/// is permitted (it doesn't move). Standardises the `reduceMotion ? nil : …` pattern the views use.
enum MotionPreference {
    /// A movement/scale/spring animation — **removed** under Reduce Motion.
    static func animation(_ base: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }

    /// An opacity cross-fade — allowed under Reduce Motion (no movement), just gentler.
    static func crossFade(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.25)
    }

    /// A textual progress description so progress is **understandable without motion or haptics** — a
    /// VoiceOver user or someone with animations/haptics off still knows where they are.
    static func challengeProgressText(counted: Int, required: Int) -> String {
        "\(min(counted, required)) of \(required)"
    }
}
