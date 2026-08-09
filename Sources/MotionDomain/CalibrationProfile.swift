import Foundation

/// A stored, **anonymized** motion calibration profile (WG-075) — the analyzer thresholds tuned by
/// the real-device calibration study, referenced from an alarm's challenge by `CalibrationProfileID`.
/// It stores **only tuning parameters**: no participant identifier, no name / device, no raw samples,
/// so a persisted or shared profile reveals nothing about who was measured (acceptance: no participant
/// identifiers are stored). Because `WalkRequirements` **re-clamps on decode**, a profile can only make
/// the walk challenge *stricter*, never weaker — the ten-second floor always re-holds.
///
/// A consumer applies a profile by passing its fields to the analyzers, e.g.
/// `WalkVerifier(requirements: profile.walk)` or `CadenceRegularity.verify(_, thresholds:
/// profile.cadence)`.
struct CalibrationProfile: Codable, Sendable, Equatable {
    let id: CalibrationProfileID
    /// Device-carried / pickup thresholds (WG-065).
    let deviceMotion: DeviceMotionEvidenceAnalyzer.Thresholds
    /// Altimeter evidence thresholds (WG-066).
    let altitude: AltitudeEvidenceAnalyzer.Thresholds
    /// Ten-second walk requirements (WG-069) — safe-bounds re-clamped on decode.
    let walk: WalkRequirements
    /// Cadence-regularity / anti-shake thresholds (WG-070).
    let cadence: CadenceThresholds

    /// The pre-study **baseline** — every analyzer's cautious `.default`. The real-device study (its
    /// test matrix + procedure live in `docs/CALIBRATION.md`) replaces these with tuned values; until
    /// the study runs, the app operates on this baseline. The chosen thresholds are recorded in the
    /// WG-075 ADR.
    static func baseline(id: CalibrationProfileID) -> CalibrationProfile {
        CalibrationProfile(
            id: id, deviceMotion: .default, altitude: .default, walk: WalkRequirements(),
            cadence: .default)
    }
}
