import Foundation

/// A wall-clock time of day. Out-of-range values cannot be represented — the
/// initializer (and `Decodable`) reject anything outside 00:00–23:59.
struct TimeOfDay: Codable, Sendable, Equatable, Hashable, Comparable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw DomainError.invalidTimeOfDay(hour: hour, minute: minute)
        }
        self.hour = hour
        self.minute = minute
    }

    private enum CodingKeys: String, CodingKey {
        case hour, minute
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            hour: container.decode(Int.self, forKey: .hour),
            minute: container.decode(Int.self, forKey: .minute))
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

/// A day on the proleptic Gregorian calendar. The initializer rejects dates that
/// do not exist (e.g. 2026-02-30). Whether the date is *reachable* in a given
/// time zone (DST gaps) is a scheduling concern (WG-020/WG-022), not the model's.
struct CalendarDate: Codable, Sendable, Equatable, Hashable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) throws {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard components.isValidDate(in: Calendar(identifier: .gregorian)) else {
            throw DomainError.invalidCalendarDate(year: year, month: month, day: day)
        }
        self.year = year
        self.month = month
        self.day = day
    }

    private enum CodingKeys: String, CodingKey {
        case year, month, day
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            year: container.decode(Int.self, forKey: .year),
            month: container.decode(Int.self, forKey: .month),
            day: container.decode(Int.self, forKey: .day))
    }
}

/// A day of the week. Raw values match Foundation's `Calendar` weekday (1 = Sunday).
enum Weekday: Int, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
}

/// A non-empty set of weekdays for a weekly recurrence. An empty recurrence is
/// unrepresentable.
struct WeekdaySet: Codable, Sendable, Equatable, Hashable {
    let days: Set<Weekday>

    init(_ days: Set<Weekday>) throws {
        guard !days.isEmpty else { throw DomainError.emptyWeekdaySet }
        self.days = days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(Set<Weekday>.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(days)
    }
}
