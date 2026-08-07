import Foundation

/// One raw motion-activity classification — the framework-neutral value a live activity source
/// hands to the mapper (WG-064). It carries CMMotionActivity's mutually-non-exclusive classifier
/// flags verbatim (several can be true at once, or none), plus the classifier's confidence as the
/// domain `quality` and the reading's timestamp, so the *resolution* to a single domain kind is
/// pure and testable without CoreMotion (`CMMotionActivity` has no public initializer).
struct MotionActivityReading: Sendable, Equatable {
    let timestamp: Date
    /// The classifier's own confidence, mapped to `quality` — for this source the two are the same
    /// axis (see `MotionActivitySample`).
    let quality: MotionSampleQuality
    let stationary: Bool
    let walking: Bool
    let running: Bool
    let cycling: Bool
    let automotive: Bool
    /// The classifier explicitly reported "no confident classification" — distinct from simply
    /// having no flag set, though both resolve to `.unknown`.
    let unknown: Bool

    init(
        timestamp: Date, quality: MotionSampleQuality, stationary: Bool = false,
        walking: Bool = false, running: Bool = false, cycling: Bool = false,
        automotive: Bool = false, unknown: Bool = false
    ) {
        self.timestamp = timestamp
        self.quality = quality
        self.stationary = stationary
        self.walking = walking
        self.running = running
        self.cycling = cycling
        self.automotive = automotive
        self.unknown = unknown
    }
}

/// The live activity-updates seam a motion-activity adapter drives — the port wrapping
/// `CMMotionActivityManager`'s start/stop-updates callback (architecture: Core Motion behind a
/// protocol), so the streaming and cancellation composition is testable off-device with a fake. The
/// real conformer lives in `MotionInfrastructure`. Note the CMMotionActivity handler carries neither
/// a start date nor an error channel — activity updates simply stream until stopped.
protocol MotionActivityUpdates: Sendable {
    func start(handler: @escaping @Sendable (MotionActivityReading?) -> Void)
    /// Stop delivery. **Idempotent** — called on stream termination and cancellation, possibly when
    /// updates were never started.
    func stop()
}

extension MotionActivityReading {
    /// The single domain kind, resolved **conservatively**: an explicit `unknown`, no flag at all,
    /// or *any* multi-flag ambiguity all resolve to `.unknown`. Only one unambiguous flag yields a
    /// concrete class. This fails safe for the anti-cheat — the risk is a *false* "walking" letting
    /// a still user pass, so an ambiguous reading (e.g. walking + automotive during a transition) is
    /// never reported as a confident single class; `.unknown` is non-passing and never evidence.
    /// Under-claiming a real walk as `.unknown` only makes the challenge harder (fails closed).
    var resolvedKind: MotionActivityKind {
        if unknown { return .unknown }
        let present: [MotionActivityKind] = [
            stationary ? .stationary : nil, walking ? .walking : nil, running ? .running : nil,
            cycling ? .cycling : nil, automotive ? .automotive : nil,
        ].compactMap { $0 }
        return present.count == 1 ? present[0] : .unknown
    }

    /// The domain sample, retaining the classifier's confidence (`quality`) and timestamp
    /// (acceptance: confidence and timestamps are retained). `nil` iff the timestamp is non-finite —
    /// a corrupt reading is dropped rather than emitted with a garbage time.
    func sample() -> MotionActivitySample? {
        guard timestamp.timeIntervalSince1970.isFinite else { return nil }
        return MotionActivitySample(timestamp: timestamp, quality: quality, kind: resolvedKind)
    }
}

extension MotionSourceAvailability {
    /// The activity classifier's availability from the hardware capability and the shared Motion &
    /// Fitness authorization. Absent hardware dominates a grant; otherwise the authorization decides
    /// — a not-yet-determined grant can't deliver, so it reads as `.notAuthorized` (the permission
    /// *flow*, WG-061, owns asking). Mirrors `forPedometer`: both read the same Motion & Fitness
    /// grant, so an unsupported device (no activity classifier) degrades to `.notPresent` safely.
    static func forMotionActivity(
        activityAvailable: Bool, authorization: MotionAuthorizationStatus
    ) -> MotionSourceAvailability {
        guard activityAvailable else { return .notPresent }
        switch authorization {
        case .authorized: return .available
        case .denied, .notDetermined: return .notAuthorized
        case .restricted: return .restricted
        }
    }
}
