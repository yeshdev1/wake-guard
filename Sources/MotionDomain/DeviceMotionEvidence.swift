import Foundation

/// The *character* of recent device motion inferred from a window of `DeviceMotionSample` — never a
/// displacement claim (WG-065). CMDeviceMotion exposes acceleration, rotation, and a gravity
/// orientation scalar but **never position**; integrating acceleration into a distance is
/// drift-dominated and dishonest, so this classifies *how* the device moved, never *how far*. It is
/// **supporting evidence only** — a movement inference alone never suppresses an alarm
/// (SAFETY_INVARIANTS) — and feeds the episode builder / challenge, which decide what it implies.
/// String-raw so an unknown persisted value fails to decode (#27) rather than being trusted.
enum DeviceMotionCharacter: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// Too few / too corrupt samples, no usable orientation, or a genuinely ambiguous signal — the
    /// conservative default. Never a positive claim.
    case insufficient
    /// The device lay still: negligible acceleration and rotation and a fixed orientation.
    case stationary
    /// Consistent with the device being lifted / carried: a clear, settled reorientation with
    /// non-violent motion. Never claimed for erratic or forceful motion. It deliberately does **not**
    /// exclude a stationary hand-tilt — tilting the phone without getting up looks the same to the
    /// sensors — so a consumer must treat `pickup` as weak carry evidence only, **never** as walking
    /// or displacement. The real wake gate is the ten-second walking verification (WG-069).
    case pickup
    /// High or erratic acceleration/rotation with an unsettled orientation and no net reorientation
    /// — the shake-on-nightstand pattern; explicitly distinguished from `pickup` so a shake can't
    /// masquerade as a carry (anti-cheat).
    case irregularShaking
}

/// Device-carried / pickup evidence over a bounded window (WG-065): the inferred motion character
/// plus the window it summarized. Carries **no distance or position** — by construction it cannot
/// claim physical displacement (see `DeviceMotionCharacter`).
struct DeviceMotionEvidence: Sendable, Equatable, Hashable, Codable {
    let character: DeviceMotionCharacter
    let sampleCount: Int
    /// The window the evidence summarizes; `nil` only when there were no samples at all.
    let windowStart: Date?
    let windowEnd: Date?

    /// The empty result — no samples, so no claim.
    static let empty = DeviceMotionEvidence(
        character: .insufficient, sampleCount: 0, windowStart: nil, windowEnd: nil)
}

/// Infers `DeviceMotionEvidence` from a window of device-motion samples, **conservatively**: it
/// prefers `insufficient` / `stationary` over a false `pickup`, and a shake is never credited as a
/// carry. Pure and deterministic — the CMDeviceMotion adapter (or the challenge runtime) supplies
/// the window; this makes no framework calls and reads no clock.
enum DeviceMotionEvidenceAnalyzer {

    /// Tunable decision thresholds. The defaults are cautious starting points and **must be
    /// calibrated on-device** alongside the battery-cost measurement (WG-065 real-device checklist);
    /// they deliberately favour `insufficient`/`stationary` over a false `pickup`.
    struct Thresholds: Sendable, Equatable, Codable {
        /// Below this many samples (or usable orientation readings) → `insufficient`.
        var minSamples: Int
        /// Max user-acceleration magnitude (g, gravity removed) to still count as "still".
        var stationaryMaxAcceleration: Double
        /// Max rotation-rate magnitude (rad/s) to still count as "still".
        var stationaryMaxRotation: Double
        /// Max spread of the gravity angle (rad) to still count as a fixed orientation.
        var stationaryMaxAngleRange: Double
        /// Min *net* (settled) reorientation (rad) required to call a motion a `pickup`.
        var pickupMinAngleChange: Double
        /// Acceleration (g) at/above which motion is "forceful" — disqualifies a `pickup`.
        var shakingMinAcceleration: Double
        /// Gravity-angle spread (rad) at/above which orientation is "erratic".
        var shakingMinAngleVariability: Double

        static let `default` = Thresholds(
            minSamples: 5, stationaryMaxAcceleration: 0.05, stationaryMaxRotation: 0.1,
            stationaryMaxAngleRange: 0.1, pickupMinAngleChange: 0.5, shakingMinAcceleration: 0.8,
            shakingMinAngleVariability: 0.5)
    }

    static func evaluate(
        _ samples: [DeviceMotionSample], thresholds: Thresholds = .default
    ) -> DeviceMotionEvidence {
        guard let first = samples.first, let last = samples.last else { return .empty }

        func evidence(_ character: DeviceMotionCharacter) -> DeviceMotionEvidence {
            DeviceMotionEvidence(
                character: character, sampleCount: samples.count,
                windowStart: first.timestamp, windowEnd: last.timestamp)
        }

        // Corrupt magnitudes or too few samples → no claim.
        let magnitudesFinite = samples.allSatisfy {
            $0.userAccelerationMagnitude.isFinite && $0.rotationRateMagnitude.isFinite
        }
        guard samples.count >= thresholds.minSamples, magnitudesFinite else {
            return evidence(.insufficient)
        }

        // Orientation is required to separate a carry from a shake; without enough finite gravity
        // angles we cannot honestly distinguish them, so we make no claim.
        let angles = samples.compactMap(\.gravityAngleFromVerticalRadians).filter(\.isFinite)
        guard angles.count >= thresholds.minSamples, let minAngle = angles.min(),
            let maxAngle = angles.max()
        else {
            return evidence(.insufficient)
        }

        let maxAcceleration = samples.map(\.userAccelerationMagnitude).max() ?? 0
        let maxRotation = samples.map(\.rotationRateMagnitude).max() ?? 0
        let angleRange = maxAngle - minAngle
        // Net reorientation from a head/tail *median*, not the raw first/last angle, so a single
        // glitched endpoint sample can't manufacture (or mask) a settled reorientation and fake a
        // pickup (WG-065 review A2a). The raw min/max range above stays glitch-inclusive — a wide
        // range only biases toward the conservative shaking/insufficient, never a false pickup.
        let netAngleChange = abs(
            Self.median(angles.suffix(Self.orientationEndpointSamples))
                - Self.median(angles.prefix(Self.orientationEndpointSamples)))

        // Still: negligible motion and a fixed orientation.
        if maxAcceleration <= thresholds.stationaryMaxAcceleration
            && maxRotation <= thresholds.stationaryMaxRotation
            && angleRange <= thresholds.stationaryMaxAngleRange
        {
            return evidence(.stationary)
        }

        // Shake: forceful or erratic motion that did NOT settle at a new orientation. Checked before
        // pickup so an ambiguous case can't be credited as a carry.
        if netAngleChange < thresholds.pickupMinAngleChange
            && (maxAcceleration >= thresholds.shakingMinAcceleration
                || angleRange >= thresholds.shakingMinAngleVariability)
        {
            return evidence(.irregularShaking)
        }

        // Pickup: a clear, settled reorientation with non-violent motion.
        if netAngleChange >= thresholds.pickupMinAngleChange
            && maxAcceleration < thresholds.shakingMinAcceleration
        {
            return evidence(.pickup)
        }

        // Motion that fits no class cleanly (e.g. a forceful reorientation) → conservative no-claim.
        return evidence(.insufficient)
    }

    /// How many head/tail angle samples the net-reorientation median is taken over — a true median
    /// needs ≥3 to reject a single glitched endpoint.
    private static let orientationEndpointSamples = 3

    private static func median(_ values: ArraySlice<Double>) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
