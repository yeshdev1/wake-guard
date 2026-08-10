import Foundation

/// A framework-independent sleep category (WG-122). HealthKit's granular asleep stages
/// (unspecified / core / deep / REM) all collapse to `.asleep` — the sleep *estimate* needs time-asleep,
/// not stages — while `.inBed` and `.awake` stay distinct.
enum SleepCategory: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case inBed
    case asleep
    case awake

    /// Priority when samples overlap (WG-122): the more-specific / awake state wins. You are not "asleep"
    /// during an overlapping "awake"; "asleep" and "awake" are more specific than merely "in bed".
    var overlapPriority: Int {
        switch self {
        case .awake: 3
        case .asleep: 2
        case .inBed: 1
        }
    }

    /// Map a HealthKit `HKCategoryValueSleepAnalysis` **raw value** to a domain category (WG-122). The raw
    /// integers are stable API constants — encoded here so the mapping is **pure and testable without
    /// importing HealthKit** (the adapter passes `sample.value`). An unknown / future value is `nil`
    /// (skipped, **fail-closed** — never silently miscounted, #27-adjacent).
    ///
    /// `inBed = 0`, `asleepUnspecified = 1`, `awake = 2`, `asleepCore = 3`, `asleepDeep = 4`,
    /// `asleepREM = 5`.
    init?(healthKitSleepValue value: Int) {
        switch value {
        case 0: self = .inBed
        case 1, 3, 4, 5: self = .asleep
        case 2: self = .awake
        default: return nil
        }
    }
}

/// A single sleep interval with its category (WG-122). A transient value used to compute a sleep estimate
/// (WG-123) and then discarded — **not** a persisted raw sample (#41, compute-and-discard, WG-120).
struct SleepSample: Sendable, Equatable, Hashable {
    let category: SleepCategory
    let interval: DateInterval

    init(category: SleepCategory, interval: DateInterval) {
        self.category = category
        self.interval = interval
    }

    /// Convenience — returns `nil` for a malformed (`end <= start`) interval rather than trapping, so a
    /// bad HealthKit sample is skipped, never a crash.
    init?(category: SleepCategory, start: Date, end: Date) {
        guard end > start else { return nil }
        self.init(category: category, interval: DateInterval(start: start, end: end))
    }
}
