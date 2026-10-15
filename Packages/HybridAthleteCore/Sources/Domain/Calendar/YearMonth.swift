import Foundation

/// A calendar month with no day, time or time zone.
public struct YearMonth: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    /// 1 to 12.
    public let month: Int

    public init(year: Int, month: Int) {
        // Normalizes months outside 1...12, so adding(months:) can overflow freely.
        let zeroBased = year * 12 + (month - 1)
        self.year = Int((Double(zeroBased) / 12).rounded(.down))
        self.month = zeroBased - self.year * 12 + 1
    }

    public init(_ date: LocalDate) {
        self.init(year: date.year, month: date.month)
    }

    /// Parses "yyyy-MM".
    public init?(_ text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return nil }
        self.init(year: parts[0], month: parts[1])
    }

    public var firstDay: LocalDate { LocalDate(year: year, month: month, day: 1) }

    public var dayCount: Int { firstDay.days(to: adding(months: 1).firstDay) }

    public func adding(months: Int) -> YearMonth {
        YearMonth(year: year, month: month + months)
    }

    public func contains(_ date: LocalDate) -> Bool {
        date.year == year && date.month == month
    }

    /// "2026-10".
    public var description: String {
        String(format: "%04d-%02d", year, month)
    }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// The months a plan's calendar can show.
public enum CalendarRange {
    /// From the plan start's month to race day's month, both included.
    public static func months(of plan: TrainingPlan) -> [YearMonth] {
        let first = YearMonth(plan.planStart)
        let last = YearMonth(plan.race.raceDate)
        guard first <= last else { return [first] }
        var months: [YearMonth] = []
        var month = first
        while month <= last {
            months.append(month)
            month = month.adding(months: 1)
        }
        return months
    }

    /// `month` moved into the plan's range: before it is the first month, after it the last.
    public static func clamp(_ month: YearMonth, to plan: TrainingPlan) -> YearMonth {
        let months = months(of: plan)
        guard let first = months.first, let last = months.last else { return month }
        return min(max(month, first), last)
    }
}
