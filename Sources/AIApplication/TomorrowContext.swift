import Foundation

/// A stable internal factor identifier the Tomorrow Agent may reason over (WG-167). A proposal (WG-168) or
/// explanation (WG-169) can only cite these IDs — an unrecognized citation is dropped — so every AI claim
/// traces to a real, recorded factor (#32).
enum TomorrowFactorID: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case earliestObligation
    case latestSafeWake
    case sleepDebt
    case readiness
}

/// A data source whose factors may be present or absent (WG-167). When access is missing, the source is
/// listed in `unavailableSources` so the model knows data is *absent*, not *zero*.
enum TomorrowContextSource: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case calendar
    case health
}

/// A single minimized, structured factor (WG-167). `value` is a short, **non-sensitive** rendering — a
/// time (`"06:45"`) or a coarse band (`"moderate"`) — **never** a calendar title, journal text, or raw
/// health sample (#35/#41).
struct TomorrowFactor: Sendable, Equatable, Hashable {
    let id: TomorrowFactorID
    let value: String
}

/// The Tomorrow Agent's context (WG-167): a set of minimized structured factors plus the sources whose
/// permission is missing. It carries **no raw text and no alarm authority** — it is the inert, text-free
/// input the model (WG-168) reasons over.
struct TomorrowContext: Sendable, Equatable, Hashable {
    let factors: [TomorrowFactor]
    let unavailableSources: [TomorrowContextSource]

    var factorIDs: Set<TomorrowFactorID> { Set(factors.map(\.id)) }

    func value(for id: TomorrowFactorID) -> String? {
        factors.first { $0.id == id }?.value
    }
}

/// The inputs to the context builder (WG-167) — already-computed domain values (each optional / coarse) and
/// the coarse access states. Grouped so the builder stays a single, testable call.
struct TomorrowContextInputs: Sendable {
    var earliestEvent: RedactedEventSummary?
    var latestSafeWake: LatestSafeWakePlan?
    var sleepDebt: SleepDebtEstimate?
    var readiness: ReadinessAssessment?
    var calendarAccess: CalendarAccessState
    var healthAccess: HealthAccessSummary

    init(
        earliestEvent: RedactedEventSummary? = nil, latestSafeWake: LatestSafeWakePlan? = nil,
        sleepDebt: SleepDebtEstimate? = nil, readiness: ReadinessAssessment? = nil,
        calendarAccess: CalendarAccessState = .notDetermined,
        healthAccess: HealthAccessSummary = .notDetermined
    ) {
        self.earliestEvent = earliestEvent
        self.latestSafeWake = latestSafeWake
        self.sleepDebt = sleepDebt
        self.readiness = readiness
        self.calendarAccess = calendarAccess
        self.healthAccess = healthAccess
    }
}

/// Assembles the Tomorrow Agent's minimized context from already-computed domain values (WG-167). A pure
/// function: it only ever emits **coarse, text-free** factor values (times and bands), reuses the
/// text-free `RedactedEventSummary` (so a calendar title can never enter), and lists any source whose
/// permission is missing rather than silently omitting it.
struct TomorrowContextBuilder: Sendable {

    func build(
        _ inputs: TomorrowContextInputs, timeZone: TimeZone,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> TomorrowContext {
        var factors: [TomorrowFactor] = []
        var unavailable: [TomorrowContextSource] = []

        if inputs.calendarAccess == .granted {
            if let event = inputs.earliestEvent {
                factors.append(
                    TomorrowFactor(
                        id: .earliestObligation,
                        value: Self.time(event.start, timeZone: timeZone, calendar: calendar)))
            }
            if let plan = inputs.latestSafeWake {
                factors.append(
                    TomorrowFactor(
                        id: .latestSafeWake,
                        value: Self.time(
                            plan.latestSafeWake, timeZone: timeZone, calendar: calendar)))
            }
        } else {
            unavailable.append(.calendar)
        }

        if inputs.healthAccess == .granted || inputs.healthAccess == .partial {
            if let level = inputs.readiness?.level {
                factors.append(TomorrowFactor(id: .readiness, value: level.rawValue))
            }
            if let debt = inputs.sleepDebt {
                factors.append(TomorrowFactor(id: .sleepDebt, value: Self.debtBand(debt.debt)))
            }
        } else {
            unavailable.append(.health)
        }

        return TomorrowContext(factors: factors, unavailableSources: unavailable)
    }

    private static func time(_ date: Date, timeZone: TimeZone, calendar: Calendar) -> String {
        var zoned = calendar
        zoned.timeZone = timeZone
        let components = zoned.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    /// A coarse sleep-debt band from accumulated debt seconds — never the raw value.
    private static func debtBand(_ debtSeconds: TimeInterval) -> String {
        let hours = debtSeconds / 3_600
        switch hours {
        case ..<0.5: return "none"
        case ..<1.5: return "mild"
        case ..<3: return "moderate"
        default: return "high"
        }
    }
}
