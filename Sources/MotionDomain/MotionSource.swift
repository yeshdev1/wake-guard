import Foundation

// MARK: - Sample quality + the common sample contract

/// How much to trust a motion sample. String-raw so an unknown value fails to decode rather than
/// being silently trusted (#27).
enum MotionSampleQuality: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case low
    case medium
    case high
}

/// A normalized motion sample. Every source's sample records **when** it was measured and **how
/// much to trust it**, so the walk challenge and awake-inference can weight by quality and reject
/// stale data — never a bare number without provenance.
///
/// **Validation.** These are simple carriers of measured data; their raw framework values are
/// validated where they enter — the `MotionInfrastructure` adapter boundary (WG-062) — and
/// re-validated on decode once a *persisted* motion-history store exists (WG-081). See the WG-060
/// ADR in `docs/DECISIONS.md` for why validation lives at the boundary rather than in the carrier.
protocol MotionSample: Sendable, Equatable {
    var timestamp: Date { get }
    var quality: MotionSampleQuality { get }
}

// MARK: - Normalized samples (framework-neutral; the CoreMotion mapping lives in MotionInfrastructure)

/// Steps / distance / cadence at a moment, normalized from a pedometer (CMPedometer).
struct PedometerSample: MotionSample, Codable, Hashable {
    let timestamp: Date
    let quality: MotionSampleQuality
    /// Cumulative steps within the current monitoring episode (mirrors `CMPedometerData`), **not**
    /// a per-sample delta — a consumer computes progress from differences and must be robust to
    /// duplicate/replayed samples so they cannot inflate it (anti-replay is WG-070's job).
    let stepCount: Int
    let distanceMeters: Double?
    /// A smoothed average cadence. The **regularity** of gait (the shake-vs-walk discriminator) is
    /// derived from the series of `secondsSinceLastStep` across the stream, not from this scalar.
    let cadenceStepsPerSecond: Double?
    /// Seconds since the previous step, when known. Streamed across samples this yields the
    /// inter-step-interval series the anti-cheat needs to measure cadence *variance* — a steady
    /// rhythmic tap is regular but implausibly so; a real gait varies within a band (WG-069/070).
    let secondsSinceLastStep: Double?

    init(
        timestamp: Date, quality: MotionSampleQuality, stepCount: Int,
        distanceMeters: Double? = nil, cadenceStepsPerSecond: Double? = nil,
        secondsSinceLastStep: Double? = nil
    ) {
        self.timestamp = timestamp
        self.quality = quality
        self.stepCount = stepCount
        self.distanceMeters = distanceMeters
        self.cadenceStepsPerSecond = cadenceStepsPerSecond
        self.secondsSinceLastStep = secondsSinceLastStep
    }
}

/// The classified activity, normalized from a motion-activity source (CMMotionActivity). Unknown
/// decodes to a decode error (#27), not `.unknown` — a corrupt value must never masquerade as a
/// real classification.
enum MotionActivityKind: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case stationary
    case walking
    case running
    case cycling
    case automotive
    /// The source itself reported "no confident classification" — a legitimate live value,
    /// distinct from a corrupt/undecodable one; the challenge treats it as non-passing (ambiguous),
    /// never as evidence.
    case unknown
}

/// A classified-activity sample. For this source, the inherited `quality` **is** the classifier's
/// confidence (`CMMotionActivity.confidence` maps to it), so a barely-cleared `.walking` is
/// distinguishable from a high-confidence one (#27 / WG-064). If WG-064 needs reading-trust and
/// classifier-confidence as separate axes, it adds the second axis to this one type (a localized
/// change — the ports are independent).
struct MotionActivitySample: MotionSample, Codable, Hashable {
    let timestamp: Date
    let quality: MotionSampleQuality
    let kind: MotionActivityKind
}

/// Summarized device motion, normalized from CMDeviceMotion — the raw axis vectors stay in the
/// infrastructure adapter; the domain reasons over magnitudes + a single orientation scalar only
/// (data minimization).
struct DeviceMotionSample: MotionSample, Codable, Hashable {
    let timestamp: Date
    let quality: MotionSampleQuality
    /// User-acceleration magnitude in g (gravity removed).
    let userAccelerationMagnitude: Double
    /// Rotation-rate magnitude in radians per second.
    let rotationRateMagnitude: Double
    /// The angle of the gravity vector from vertical, in radians, when known — a privacy-safe
    /// scalar (not the raw axes) whose stability over the stream separates a phone **carried** by a
    /// walker (a slowly-varying tilt) from one **shaken** on a nightstand (an erratic one), so a
    /// vigorous shake can't win on magnitude alone (device-carried evidence, WG-065).
    let gravityAngleFromVerticalRadians: Double?

    init(
        timestamp: Date, quality: MotionSampleQuality, userAccelerationMagnitude: Double,
        rotationRateMagnitude: Double, gravityAngleFromVerticalRadians: Double? = nil
    ) {
        self.timestamp = timestamp
        self.quality = quality
        self.userAccelerationMagnitude = userAccelerationMagnitude
        self.rotationRateMagnitude = rotationRateMagnitude
        self.gravityAngleFromVerticalRadians = gravityAngleFromVerticalRadians
    }
}

/// Relative altitude / pressure, normalized from a barometric altimeter (CMAltimeter). Supporting
/// evidence only — an absent barometer (`.notPresent`) simply isn't consulted and never weakens or
/// falsely fails a challenge (WG-066).
struct AltitudeSample: MotionSample, Codable, Hashable {
    let timestamp: Date
    let quality: MotionSampleQuality
    let relativeAltitudeMeters: Double
    let pressureKilopascals: Double?
}

// MARK: - Availability + errors

/// Whether a motion source can provide data. **Explicit** — never a silent nil — so the caller
/// must offer a safe fallback (e.g. the accessible challenge) when a source can't deliver, and a
/// challenge is never falsely failed because a sensor was quietly missing (#21 spirit). String-raw
/// so an unknown value fails to decode (#27).
enum MotionSourceAvailability: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// Present, authorized, and delivering.
    case available
    /// The hardware is absent on this device (e.g. no barometer / no step counter).
    case notPresent
    /// Motion & Fitness permission is not granted — the request flow is WG-061.
    case notAuthorized
    /// Parental controls / MDM forbid motion access; unlike `.notAuthorized` a Settings toggle
    /// won't fix it.
    case restricted
    /// Present and authorized, but not delivering right now (paused / transient error).
    case temporarilyUnavailable
}

/// A definite motion-source failure surfaced through a sample stream.
enum MotionSourceError: Error, Sendable, Equatable, Hashable {
    /// The stream stopped (or never started) because the source is unavailable for this reason.
    case unavailable(MotionSourceAvailability)
}

// MARK: - Independent source ports

/// Steps / distance / cadence (CMPedometer). One of four **independent** motion ports, so the
/// walk challenge and awake-inference depend on exactly the sources they need and degrade
/// gracefully when one is unavailable. Domain-owned and Foundation-only — the CoreMotion-backed
/// adapter lives in `MotionInfrastructure`, and tests use `FakePedometerSource`.
///
/// `samples()` **contract** (applies to all four ports): each call begins a **new, independent,
/// live** stream — it is not replayable and does not buffer history (a *historical, bounded-window*
/// query is a separate port, WG-062/081). Cancel by cancelling the consuming task. Any thrown error
/// is **terminal** (the source dropped out) — a consumer must treat it, and any non-`MotionSourceError`
/// throw, as "keep the alarm, offer the fallback" (fail-closed, #24), never a challenge failure.
/// Sample timestamps are **not** guaranteed monotonic or fresh; consumers reject stale / out-of-order
/// samples (WG-063/067).
protocol PedometerSource: Sendable {
    /// The current availability — a value, never a thrown error.
    func availability() async -> MotionSourceAvailability
    /// A live stream of samples (see the port contract above).
    func samples() -> AsyncThrowingStream<PedometerSample, Error>
    /// When Motion & Fitness is **not yet determined**, trigger the system permission prompt (Core Motion
    /// only asks once a query starts — there is no request API), then return the resolved availability. A
    /// definite state (authorized / denied / restricted / absent) is returned unchanged. The in-context ask
    /// the challenge uses (WG-061); only the live CoreMotion adapter overrides it.
    func requestAuthorization() async -> MotionSourceAvailability
}

extension PedometerSource {
    /// Default: nothing to prompt for (test/preview sources and the non-live adapters) — report current
    /// availability so a caller can treat "no live source" and "denied" identically (the safe fallback).
    func requestAuthorization() async -> MotionSourceAvailability { await availability() }
}

/// Classified activity (CMMotionActivity). See the `PedometerSource` `samples()` contract.
protocol MotionActivitySource: Sendable {
    func availability() async -> MotionSourceAvailability
    func samples() -> AsyncThrowingStream<MotionActivitySample, Error>
}

/// Accelerometer/gyro-derived device motion (CMDeviceMotion). See the `PedometerSource` `samples()`
/// contract.
protocol DeviceMotionSource: Sendable {
    func availability() async -> MotionSourceAvailability
    func samples() -> AsyncThrowingStream<DeviceMotionSample, Error>
}

/// Barometric relative altitude (CMAltimeter). See the `PedometerSource` `samples()` contract.
protocol AltimeterSource: Sendable {
    func availability() async -> MotionSourceAvailability
    func samples() -> AsyncThrowingStream<AltitudeSample, Error>
}
