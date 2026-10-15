import Foundation

/// A calendar day with no time or time zone, so moving between zones never shifts it.
/// Encoded as "yyyy-MM-dd".
public struct LocalDate: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// The local day a moment falls on, e.g. a run starting at 23:30 local time
    /// belongs to that day even when it is already the next day in UTC.
    public init(date: Date, calendar: Calendar) {
        self.init(date, calendar: calendar)
    }

    /// Parses "yyyy-MM-dd".
    public init?(_ text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        let candidate = LocalDate(year: parts[0], month: parts[1], day: parts[2])
        // Reject impossible days such as 31 April by round-tripping.
        guard LocalDate(daysSinceEpoch: candidate.daysSinceEpoch) == candidate else { return nil }
        self = candidate
    }

    /// Days since 1970-01-01 (Howard Hinnant's civil-date algorithm).
    public var daysSinceEpoch: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    public init(daysSinceEpoch days: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(daysSinceEpoch: daysSinceEpoch + days)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(to other: LocalDate) -> Int {
        other.daysSinceEpoch - daysSinceEpoch
    }

    public var weekday: Weekday {
        // 1970-01-01 was a Thursday; Monday is index 0.
        Weekday.allCases[((daysSinceEpoch + 3) % 7 + 7) % 7]
    }

    /// Midnight at the start of this day in `calendar`'s time zone, for display.
    public func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        lhs.daysSinceEpoch < rhs.daysSinceEpoch
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let date = LocalDate(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected yyyy-MM-dd"))
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Days of the week, Monday first.
public enum Weekday: String, Sendable, CaseIterable, Codable, Comparable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    /// 0 for Monday through 6 for Sunday.
    public var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    public var letter: String {
        switch self {
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        case .sunday: "S"
        }
    }

    public var name: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    public var isWeekend: Bool {
        self == .saturday || self == .sunday
    }

    /// Days apart going around the week either way, 0 to 3.
    public func distance(to other: Weekday) -> Int {
        let gap = abs(index - other.index)
        return min(gap, 7 - gap)
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.index < rhs.index
    }
}
