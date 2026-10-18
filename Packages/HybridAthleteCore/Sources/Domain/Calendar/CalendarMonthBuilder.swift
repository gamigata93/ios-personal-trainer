import Foundation

/// One day in the month grid.
public struct CalendarCell: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Before the plan start: dimmed and not selectable.
        case beforePlan
        /// planStart <= date <= race day.
        case inPlan
        /// After race day: dimmed and not selectable.
        case afterRace
    }

    public let date: LocalDate
    public let isToday: Bool
    public let session: PlannedSession?
    public let status: SessionStatus?
    public let isRaceDay: Bool
    public let kind: Kind
    public var strength: StrengthSession? = nil
    public var strengthStatus: SessionStatus? = nil

    public var isSelectable: Bool { kind == .inPlan }
}

/// One month of the training calendar, Monday first.
public struct CalendarMonth: Sendable, Equatable {
    public let month: YearMonth
    /// "October 2026".
    public let title: String
    /// M T W T F S S.
    public let weekdayLabels: [String]
    /// Blanks before the 1st, so it sits under its weekday.
    public let leadingBlanks: Int
    /// Blanks after the last day, to a full row of 7.
    public let trailingBlanks: Int
    /// The 1st to the last day of the month.
    public let cells: [CalendarCell]
    public let isFirstMonth: Bool
    public let isLastMonth: Bool

    /// Blanks plus days: always a multiple of 7.
    public var slotCount: Int { leadingBlanks + cells.count + trailingBlanks }

    public func cell(on date: LocalDate) -> CalendarCell? {
        cells.first { $0.date == date }
    }
}

public enum CalendarMonthBuilder {
    /// Statuses come from `PlanProgress` (the same matcher and rules as Home),
    /// so Home and the calendar can never disagree.
    public static func month(
        _ month: YearMonth, plan: TrainingPlan, runs: [CompletedRun], strength: [CompletedStrength] = [], today: LocalDate
    ) -> CalendarMonth {
        let progress = PlanProgress(plan: plan, runs: runs, strength: strength, today: today)
        let sessionsByDay = Dictionary(plan.sessions.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let strengthByDay = Dictionary(plan.strengthSessions.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let cells = (0..<month.dayCount).map { offset -> CalendarCell in
            let date = month.firstDay.adding(days: offset)
            let session = sessionsByDay[date]
            let kind: CalendarCell.Kind = date < plan.planStart ? .beforePlan : (date > plan.race.raceDate ? .afterRace : .inPlan)
            let strength = kind == .inPlan ? strengthByDay[date] : nil
            return CalendarCell(
                date: date,
                isToday: date == today,
                session: kind == .inPlan ? session : nil,
                status: kind == .inPlan ? session.map(progress.status(of:)) : nil,
                isRaceDay: date == plan.race.raceDate,
                kind: kind,
                strength: strength,
                strengthStatus: strength.map(progress.status(of:))
            )
        }
        let leading = month.firstDay.weekday.index
        let months = CalendarRange.months(of: plan)
        return CalendarMonth(
            month: month,
            title: CalendarFormat.monthTitle(month),
            weekdayLabels: Weekday.allCases.map(\.letter),
            leadingBlanks: leading,
            trailingBlanks: (7 - (leading + cells.count) % 7) % 7,
            cells: cells,
            isFirstMonth: month <= (months.first ?? month),
            isLastMonth: month >= (months.last ?? month)
        )
    }

    /// The month holding today, clamped into the plan's months.
    public static func defaultMonth(plan: TrainingPlan, today: LocalDate) -> YearMonth {
        CalendarRange.clamp(YearMonth(today), to: plan)
    }

    /// Today when it is in the month and inside the plan; race day when the race
    /// is over and its month is shown; otherwise the month's first session day.
    public static func defaultSelection(in month: CalendarMonth, plan: TrainingPlan, today: LocalDate) -> LocalDate? {
        if let cell = month.cell(on: today), cell.isSelectable { return today }
        if today > plan.race.raceDate, month.month.contains(plan.race.raceDate) { return plan.race.raceDate }
        return month.cells.first { $0.session != nil || $0.strength != nil }?.date
    }
}

/// Plain English calendar text. Pure and locale-independent.
public enum CalendarFormat {
    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// "October 2026".
    public static func monthTitle(_ month: YearMonth) -> String {
        "\(monthNames[month.month - 1]) \(month.year)"
    }

    /// "Wednesday 28 October, Easy run, today", the same words as Home's week
    /// strip. Days outside the plan read "Saturday 10 October, outside the plan".
    public static func accessibilityLabel(_ cell: CalendarCell) -> String {
        guard cell.isSelectable else { return "\(HomeFormat.spokenDate(cell.date)), outside the plan" }
        return HomeFormat.dayAccessibilityLabel(
            date: cell.date, sessionName: cell.session?.name, isRaceDay: cell.isRaceDay, status: cell.status, isToday: cell.isToday,
            strength: cell.strength.flatMap { item in cell.strengthStatus.map { (item.name, $0) } }
        )
    }
}
