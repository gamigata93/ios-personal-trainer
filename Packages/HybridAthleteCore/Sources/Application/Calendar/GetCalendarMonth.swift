import Foundation
import Domain

/// Moving or swapping the session with this id on the Calendar.
public enum CalendarEditMode: Sendable, Equatable {
    case moving(sessionId: String)
    case swapping(sessionId: String)

    public var sessionId: String {
        switch self {
        case .moving(let id), .swapping(let id): id
        }
    }
}

/// One month of the Calendar tab, already worded.
public struct CalendarMonthOverview: Sendable, Equatable {
    /// A cell's part while moving or swapping.
    public enum EditRole: Sendable, Equatable {
        /// The session being moved or swapped: keeps its selection ring.
        case source
        /// A valid day to tap.
        case target
        /// Everything else: dimmed, taps ignored.
        case inactive
    }

    /// The banner under the header while moving or swapping.
    public struct EditBanner: Sendable, Equatable {
        /// "Move session" or "Swap session".
        public let title: String
        /// "Moving Easy run. Tap a free day, today or later."
        public let text: String
    }

    public struct Cell: Sendable, Equatable, Identifiable {
        public var id: String { date.description }
        public let date: LocalDate
        /// "28".
        public let dayNumber: String
        public let isToday: Bool
        public let isSelected: Bool
        public let isSelectable: Bool
        public let sessionType: SessionType?
        public let status: SessionStatus?
        public let isRaceDay: Bool
        public let kind: CalendarCell.Kind
        /// Nil when not moving or swapping.
        public let editRole: EditRole?
        /// "Wednesday 28 October, Easy run, today", or for a target "Thursday 29
        /// October, free day, double tap to move Easy run here".
        public let accessibilityLabel: String
    }

    public let month: YearMonth
    /// "October 2026".
    public let title: String
    public let weekdayLabels: [String]
    public let leadingBlanks: Int
    public let trailingBlanks: Int
    public let cells: [Cell]
    public let canGoBack: Bool
    public let canGoForward: Bool
    /// The selected day, or nil when the month has nothing to select.
    public let selectedDate: LocalDate?
    /// The card for the selected day.
    public let dayCard: DayCard?
    /// "Your phone is locked. Showing progress from today 07:40." Only when locked.
    public let lockedLine: String?
    /// The selected day's session id, when it has one.
    public let selectedSessionId: String?
    /// What the selected session offers; empty while editing or for completed sessions.
    public let actions: [PlanAction]
    /// Only while moving or swapping.
    public let banner: EditBanner?
}

/// Builds the calendar month from the plan, the runs and today, using the
/// Domain calendar rules.
public struct GetCalendarMonth: Sendable {
    private let clock: any Clock
    private let calendar: Calendar

    public init(clock: any Clock, calendar: Calendar) {
        self.clock = clock
        self.calendar = calendar
    }

    public var today: LocalDate { LocalDate(date: clock.now(), calendar: calendar) }

    /// The month to open on: `requested` (clamped into the plan) or the month holding today.
    public func defaultMonth(plan: TrainingPlan, requested: YearMonth? = nil) -> YearMonth {
        requested.map { CalendarRange.clamp($0, to: plan) } ?? CalendarMonthBuilder.defaultMonth(plan: plan, today: today)
    }

    /// `selected` is kept when it is a selectable day of the month; otherwise the
    /// default rule picks one.
    public func execute(
        plan: TrainingPlan,
        runs: CompletedRunsResult,
        month: YearMonth,
        selected: LocalDate?,
        mode: CalendarEditMode? = nil
    ) -> CalendarMonthOverview {
        let today = today
        let source = mode.flatMap { plan.session(id: $0.sessionId) }
        let targets = mode.map { targetDates($0, plan: plan, runs: runs.runs, today: today) } ?? []
        let shown = CalendarMonthBuilder.month(CalendarRange.clamp(month, to: plan), plan: plan, runs: runs.runs, today: today)
        let selection = selected.flatMap { shown.cell(on: $0)?.isSelectable == true ? $0 : nil }
            ?? CalendarMonthBuilder.defaultSelection(in: shown, plan: plan, today: today)
        let raceTitle = HomeFormat.raceTitle(distanceKm: plan.race.distanceKm)
        let selectedSession = selection.flatMap { shown.cell(on: $0)?.session }
        return CalendarMonthOverview(
            month: shown.month,
            title: shown.title,
            weekdayLabels: shown.weekdayLabels,
            leadingBlanks: shown.leadingBlanks,
            trailingBlanks: shown.trailingBlanks,
            cells: shown.cells.map { cell in
                CalendarMonthOverview.Cell(
                    date: cell.date,
                    dayNumber: "\(cell.date.day)",
                    isToday: cell.isToday,
                    isSelected: mode == nil ? cell.date == selection : cell.date == source?.date,
                    isSelectable: cell.isSelectable,
                    sessionType: cell.session?.type,
                    status: cell.status,
                    isRaceDay: cell.isRaceDay && cell.isSelectable,
                    kind: cell.kind,
                    editRole: role(of: cell, source: source, targets: targets, isEditing: mode != nil),
                    accessibilityLabel: accessibilityLabel(cell, mode: mode, source: source, targets: targets)
                )
            },
            canGoBack: !shown.isFirstMonth,
            canGoForward: !shown.isLastMonth,
            selectedDate: selection,
            // While editing, the card stays on the session being moved or swapped, in any month.
            dayCard: source.map { session in
                DayCard.make(
                    session: session,
                    status: PlanProgress(plan: plan, runs: runs.runs, today: today).status(of: session),
                    isRaceDay: false,
                    raceTitle: raceTitle
                )
            } ?? selection.flatMap { date in
                shown.cell(on: date).map { DayCard.make(session: $0.session, status: $0.status, isRaceDay: $0.isRaceDay, raceTitle: raceTitle) }
            },
            lockedLine: ProgressLockedLine.text(runs: runs, now: clock.now(), calendar: calendar),
            selectedSessionId: selectedSession?.id,
            actions: mode == nil
                ? selectedSession.map { PlanActions.available(session: $0, plan: plan, runs: runs.runs, today: today) } ?? []
                : [],
            banner: source.flatMap { session in mode.map { Self.banner($0, name: session.name) } }
        )
    }

    // MARK: Editing

    /// The days a tap applies the edit on.
    public func targetDates(_ mode: CalendarEditMode, plan: TrainingPlan, runs: [CompletedRun], today: LocalDate? = nil) -> Set<LocalDate> {
        let today = today ?? self.today
        switch mode {
        case .moving(let id): return PlanEditTargets.moveTargets(sessionId: id, plan: plan, runs: runs, today: today)
        case .swapping(let id): return PlanEditTargets.swapTargets(sessionId: id, plan: plan, runs: runs, today: today)
        }
    }

    /// The edit a tap on `target` makes, or nil when the day is not a valid target.
    public func edit(_ mode: CalendarEditMode, target: LocalDate, plan: TrainingPlan, runs: [CompletedRun]) -> PlanEdit? {
        guard
            targetDates(mode, plan: plan, runs: runs).contains(target),
            let session = plan.session(id: mode.sessionId)
        else { return nil }
        switch mode {
        case .moving:
            return .move(sessionId: session.id, from: session.date, to: target)
        case .swapping:
            guard let other = plan.session(on: target) else { return nil }
            return .swap(sessionIdA: session.id, sessionIdB: other.id, dateA: session.date, dateB: other.date)
        }
    }

    /// The edit a one-tap action makes (next day or missed); nil for actions that start a mode.
    public func edit(_ action: PlanAction, sessionId: String, plan: TrainingPlan) -> PlanEdit? {
        guard action.isEnabled, let session = plan.session(id: sessionId) else { return nil }
        switch action.kind {
        case .moveNextDay: return action.target.map { .move(sessionId: session.id, from: session.date, to: $0) }
        case .markMissed: return .markMissed(sessionId: session.id)
        case .moveAnotherDay, .swap: return nil
        }
    }

    private func role(of cell: CalendarCell, source: PlannedSession?, targets: Set<LocalDate>, isEditing: Bool) -> CalendarMonthOverview.EditRole? {
        guard isEditing else { return nil }
        if let source, cell.date == source.date { return .source }
        return targets.contains(cell.date) ? .target : .inactive
    }

    private func accessibilityLabel(
        _ cell: CalendarCell, mode: CalendarEditMode?, source: PlannedSession?, targets: Set<LocalDate>
    ) -> String {
        let base = CalendarFormat.accessibilityLabel(cell)
        guard let mode, let source, targets.contains(cell.date) else { return base }
        switch mode {
        case .moving: return "\(HomeFormat.spokenDate(cell.date)), free day, double tap to move \(source.name) here"
        case .swapping: return "\(base), double tap to swap with \(source.name)"
        }
    }

    private static func banner(_ mode: CalendarEditMode, name: String) -> CalendarMonthOverview.EditBanner {
        switch mode {
        case .moving:
            CalendarMonthOverview.EditBanner(title: "Move session", text: "Moving \(name). Tap a free day, today or later.")
        case .swapping:
            CalendarMonthOverview.EditBanner(title: "Swap session", text: "Swapping \(name). Tap an upcoming session to trade places.")
        }
    }
}
