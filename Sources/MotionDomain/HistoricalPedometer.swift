import Foundation

/// An error from a historical pedometer query (WG-062).
enum MotionQueryError: Error, Sendable, Equatable {
    case invalidWindow(reason: String)
    case invalidSample(reason: String)
}

/// A validated time window for a historical pedometer query. Construction enforces that the window
/// is ordered, not in the future, and bounded — so a query can never read the future or an
/// unbounded/absurd range (acceptance: queries validate intervals and timestamps).
struct PedometerQueryWindow: Sendable, Equatable, Hashable {
    let start: Date
    let end: Date

    /// The longest history a single query may span — bounds cost and staleness. Tunable.
    static let maxSpan: TimeInterval = 24 * 3600

    init(
        start: Date, end: Date, now: Date, maxSpan: TimeInterval = PedometerQueryWindow.maxSpan
    ) throws {
        // Finiteness first: `Date`'s comparisons are NaN-blind, so a non-finite `now` would let
        // `end <= now` pass and the future-read guard silently fail (WG-062 review B1).
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
            now.timeIntervalSince1970.isFinite
        else {
            throw MotionQueryError.invalidWindow(reason: "dates must be finite")
        }
        guard start < end else {
            throw MotionQueryError.invalidWindow(reason: "start must be before end")
        }
        guard end <= now else {
            throw MotionQueryError.invalidWindow(reason: "end must not be in the future")
        }
        guard end.timeIntervalSince(start) <= maxSpan else {
            throw MotionQueryError.invalidWindow(reason: "window exceeds the maximum span")
        }
        self.start = start
        self.end = end
    }
}

/// A historical (bounded-window) pedometer query — the awake-inference source (WG-062), separate
/// from the live pedometer stream (WG-063). Domain-owned; the CMPedometer-backed adapter lives in
/// `MotionInfrastructure`, and tests use `FakeHistoricalPedometerSource`.
protocol HistoricalPedometerSource: Sendable {
    func availability() async -> MotionSourceAvailability
    /// Cumulative pedometer data over the validated window. Throws `MotionSourceError.unavailable`
    /// when the source can't deliver; never logs raw samples (#41). Contract: the returned samples
    /// **aggregate-cover the whole window**, so a wider window's step total is ≥ any contained
    /// sub-window's — WG-081's recency ladder (nested windows) relies on this monotonicity.
    func samples(in window: PedometerQueryWindow) async throws -> [PedometerSample]
}

extension PedometerSample {
    /// Build a sample from raw pedometer values, **validating at the adapter boundary** — this is
    /// WG-060's deferred validation, landing where untrusted CoreMotion data enters. A negative
    /// step count, or a non-finite / negative distance, cadence, or interval is impossible sensor
    /// data and is rejected, so downstream wake logic never sees a corrupt reading. Throws
    /// `MotionQueryError.invalidSample`.
    static func validated(
        timestamp: Date, quality: MotionSampleQuality, stepCount: Int,
        distanceMeters: Double? = nil, cadenceStepsPerSecond: Double? = nil,
        secondsSinceLastStep: Double? = nil, within window: PedometerQueryWindow? = nil
    ) throws -> PedometerSample {
        guard timestamp.timeIntervalSince1970.isFinite else {
            throw MotionQueryError.invalidSample(reason: "timestamp must be finite")
        }
        // A historical sample must be stamped inside the window it answered — an endDate past the
        // window end is a future-stamped aggregate the awake-inference would misread as a fresh
        // "just moved" signal (WG-062 review S1). Only enforced when the caller supplies the window.
        if let window, timestamp < window.start || timestamp > window.end {
            throw MotionQueryError.invalidSample(
                reason: "timestamp must lie within the queried window")
        }
        guard stepCount >= 0 else {
            throw MotionQueryError.invalidSample(reason: "stepCount must be >= 0")
        }
        let measures = [distanceMeters, cadenceStepsPerSecond, secondsSinceLastStep].compactMap {
            $0
        }
        for value in measures where !value.isFinite || value < 0 {
            throw MotionQueryError.invalidSample(
                reason: "distance / cadence / interval must be finite and >= 0")
        }
        return PedometerSample(
            timestamp: timestamp, quality: quality, stepCount: stepCount,
            distanceMeters: distanceMeters, cadenceStepsPerSecond: cadenceStepsPerSecond,
            secondsSinceLastStep: secondsSinceLastStep)
    }
}

extension MotionSourceAvailability {
    /// The pedometer's availability from the hardware capability and the shared Motion & Fitness
    /// authorization: absent hardware dominates (a grant can't conjure a step counter), otherwise
    /// the authorization decides. A not-yet-determined grant can't deliver, so it reads as
    /// `.notAuthorized` (the permission *flow* — WG-061 — owns asking).
    static func forPedometer(
        stepCountingAvailable: Bool, authorization: MotionAuthorizationStatus
    ) -> MotionSourceAvailability {
        guard stepCountingAvailable else { return .notPresent }
        switch authorization {
        case .authorized: return .available
        case .denied, .notDetermined: return .notAuthorized
        case .restricted: return .restricted
        }
    }
}
