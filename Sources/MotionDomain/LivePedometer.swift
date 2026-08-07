import Foundation

/// One raw live pedometer reading — cumulative step data since the stream started, as the
/// framework-neutral value a live-updates source hands to the normalizer *before* validation
/// (WG-063). It mirrors the `CMPedometerData` fields the domain cares about; `PedometerSample` is
/// the validated, quality-tagged result the port emits.
///
/// There is deliberately **no `secondsSinceLastStep`**: CMPedometer live data exposes only a
/// smoothed `currentCadence`, never a per-step interval, so the emitted `PedometerSample` carries
/// `secondsSinceLastStep == nil` from this path. The cadence-*regularity* anti-cheat (WG-069/070)
/// must reconstruct the inter-step series from timestamp deltas + cadence (or `DeviceMotionSource`),
/// not expect it here.
struct PedometerReading: Sendable, Equatable {
    let timestamp: Date
    /// Cumulative steps since the stream's start date (mirrors `CMPedometerData.numberOfSteps`).
    let stepCount: Int
    let distanceMeters: Double?
    let cadenceStepsPerSecond: Double?

    init(
        timestamp: Date, stepCount: Int, distanceMeters: Double? = nil,
        cadenceStepsPerSecond: Double? = nil
    ) {
        self.timestamp = timestamp
        self.stepCount = stepCount
        self.distanceMeters = distanceMeters
        self.cadenceStepsPerSecond = cadenceStepsPerSecond
    }
}

/// The live-updates seam a live pedometer adapter drives — the port wrapping CMPedometer's
/// start/stop-updates callback (architecture: Core Motion is wrapped behind a protocol), so the
/// streaming, dedup, and cancellation composition is testable off-device with a fake. The real
/// CMPedometer-backed conformer lives in `MotionInfrastructure`.
protocol LivePedometerUpdates: Sendable {
    /// Begin delivering cumulative readings measured from `start`. `handler` is invoked serially,
    /// possibly on an arbitrary queue; a non-nil error is a terminal delivery for this stream.
    func start(from start: Date, handler: @escaping @Sendable (PedometerReading?, Error?) -> Void)
    /// Stop delivery. **Idempotent** — called on stream termination and cancellation, possibly when
    /// updates were never started.
    func stop()
}

/// Turns a live pedometer update sequence into a **strictly time-ordered, validated** sample series
/// (WG-063). CoreMotion makes no monotonicity or freshness guarantee (see the `PedometerSource`
/// contract) and can redeliver or reorder cumulative readings, so `accept` drops any reading that:
///   * is implausibly far in the future (past `now` + a small skew) — such a stamp would poison the
///     watermark and silently drop every later real reading, and reads as a false "just moved";
///   * does not advance past the last emitted timestamp — a duplicate or late/out-of-order delivery
///     carries no new information and must not rewind the series;
///   * regresses the cumulative step count — steps only grow within one stream, so a decrease is a
///     glitch/reset that would hand the consumer a negative progress delta (anti-*replay* of
///     duplicate samples stays WG-070's job); or
///   * fails boundary validation (WG-060's deferred check) — a single corrupt live reading is
///     skipped, not fatal, so one sensor glitch can't end a walk challenge.
/// A stream that only ever drops therefore emits nothing; the *consumer* (the challenge runtime,
/// WG-068/069) must impose the deadline that turns silence into a fail-closed timeout — this layer
/// only guarantees that what it *does* emit is ordered and well-formed. Value semantics + injected
/// `now`/readings → deterministic and trace-testable; state advances only on a successfully emitted
/// sample, so a dropped reading never corrupts ordering.
struct LivePedometerNormalizer {
    /// How far past `now` a reading's timestamp may sit before it's rejected as implausible — a
    /// small clock-skew allowance (the sample clock and `now` are the same system clock).
    static let maxFutureSkew: TimeInterval = 5

    private var lastEmitted: Date?
    private var lastStepCount: Int?

    /// The validated sample to emit, or `nil` to drop this reading (future, duplicate, out-of-order,
    /// count-regression, or invalid). `quality` is set `.high` for every live sample deliberately:
    /// the shake-vs-walk trust signal is the *regularity* of the inter-step series (WG-069/070), not
    /// this per-sample scalar, so a uniform `.high` here is not a trust input.
    mutating func accept(
        _ reading: PedometerReading, now: Date,
        maxFutureSkew: TimeInterval = LivePedometerNormalizer.maxFutureSkew
    ) -> PedometerSample? {
        // Reject an implausibly future timestamp first — before it can advance the watermark and
        // silently drop every subsequent legitimate reading (WG-063 review B1). A NaN timestamp
        // fails this `>` too (NaN compares false) and is caught by validation below.
        if reading.timestamp > now.addingTimeInterval(maxFutureSkew) { return nil }
        if let lastEmitted, reading.timestamp <= lastEmitted { return nil }
        if let lastStepCount, reading.stepCount < lastStepCount { return nil }
        guard
            let sample = try? PedometerSample.validated(
                timestamp: reading.timestamp, quality: .high, stepCount: reading.stepCount,
                distanceMeters: reading.distanceMeters,
                cadenceStepsPerSecond: reading.cadenceStepsPerSecond)
        else { return nil }
        lastEmitted = reading.timestamp
        lastStepCount = reading.stepCount
        return sample
    }
}
