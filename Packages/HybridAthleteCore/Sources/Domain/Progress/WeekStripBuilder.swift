import Foundation

/// One day in the week strip.
public struct DayCell: Sendable, Equatable {
    public let date: LocalDate
    public let isToday: Bool
    public let session: PlannedSession?
    public let status: SessionStatus?
    public let isRaceDay: Bool
    public let strength: StrengthSession?
    public let strengthStatus: SessionStatus?

    public var weekday: Weekday { date.weekday }

    public init(
        date: LocalDate, isToday: Bool, session: PlannedSession?, status: SessionStatus?, isRaceDay: Bool,
        strength: StrengthSession? = nil, strengthStatus: SessionStatus? = nil
    ) {
        self.date = date
        self.isToday = isToday
        self.session = session
        self.status = status
        self.isRaceDay = isRaceDay
        self.strength = strength
        self.strengthStatus = strengthStatus
    }
}

/// The plan week the strip shows.
public struct ShownWeek: Sendable, Equatable {
    /// 1-based plan week.
    public let index: Int
    public let weekCount: Int
    /// A Monday.
    public let startDate: LocalDate
    /// Monday to Sunday.
    public let days: [DayCell]

    public var endDate: LocalDate { startDate.adding(days: 6) }
    public var canGoBack: Bool { index > 1 }
    public var canGoForward: Bool { index < weekCount }

    public func contains(_ date: LocalDate) -> Bool {
        date >= startDate && date <= endDate
    }

    /// Today when it is in this week, otherwise the first day with a session,
    /// otherwise race day, otherwise Monday.
    public func defaultSelection(today: LocalDate) -> LocalDate {
        if contains(today) { return today }
        return days.first { $0.session != nil || $0.strength != nil }?.date
            ?? days.first { $0.isRaceDay }?.date
            ?? startDate
    }
}

public enum WeekStripBuilder {
    /// The week holding today, moved by `weekOffset` and clamped to the plan's
    /// weeks. Before the start it is week 1; after race day, the last week.
    /// Nil only for a plan without weeks.
    public static func week(progress: PlanProgress, weekOffset: Int) -> ShownWeek? {
        let plan = progress.plan
        guard !plan.weeks.isEmpty else { return nil }
        let count = plan.weeks.count
        let base = progress.currentWeekIndex ?? (progress.today < plan.planStart ? 1 : count)
        let index = min(max(base + weekOffset, 1), count)
        let week = plan.weeks[index - 1]
        let sessionsByDay = Dictionary(plan.sessions.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let strengthByDay = Dictionary(plan.strengthSessions.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let days = (0..<7).map { offset -> DayCell in
            let date = week.startDate.adding(days: offset)
            let session = sessionsByDay[date]
            let strength = strengthByDay[date]
            return DayCell(
                date: date,
                isToday: date == progress.today,
                session: session,
                status: session.map(progress.status(of:)),
                isRaceDay: date == plan.race.raceDate,
                strength: strength,
                strengthStatus: strength.map(progress.status(of:))
            )
        }
        return ShownWeek(index: index, weekCount: count, startDate: week.startDate, days: days)
    }
}
