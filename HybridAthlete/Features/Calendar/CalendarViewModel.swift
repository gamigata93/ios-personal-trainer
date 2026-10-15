import Foundation
import Observation
import Domain
import Application

/// The Calendar tab: the shown month, the selected day, and the edit flow (move,
/// swap, mark missed, undo). Every value and every valid target comes from
/// `GetCalendarMonth` over the shared plan and runs; saving goes through the
/// shared `ActivePlanStore`. No rules live here.
@MainActor
@Observable
final class CalendarViewModel {
    private(set) var month: YearMonth?
    /// Nil when idle.
    private(set) var mode: CalendarEditMode?
    private(set) var isApplying = false
    private var chosenDate: LocalDate?

    private let plans: ActivePlanStore
    private let runs: CompletedRunsStore
    private let getCalendarMonth: GetCalendarMonth
    /// DEBUG `-calendarMonth`; clamped into the plan.
    private let requestedMonth: YearMonth?

    init(plans: ActivePlanStore, runs: CompletedRunsStore, getCalendarMonth: GetCalendarMonth, requestedMonth: YearMonth? = nil) {
        self.plans = plans
        self.runs = runs
        self.getCalendarMonth = getCalendarMonth
        self.requestedMonth = requestedMonth
    }

    var overview: CalendarMonthOverview? {
        guard let plan = plans.plan else { return nil }
        return getCalendarMonth.execute(
            plan: plan,
            runs: runs.result,
            month: month ?? getCalendarMonth.defaultMonth(plan: plan, requested: requestedMonth),
            selected: chosenDate,
            mode: mode
        )
    }

    var selectedDate: LocalDate? { overview?.selectedDate }

    /// The latest edit's notice (with Undo).
    var notice: PlanEditNotice? { plans.notice }

    /// "Couldn't apply that change. Your plan is unchanged." after a failed edit or undo.
    var failureText: String? { plans.editFailed ? PlanEditFormat.failure : nil }

    /// The valid days to tap while moving or swapping.
    var targetDates: Set<LocalDate> {
        guard let mode, let plan = plans.plan else { return [] }
        return getCalendarMonth.targetDates(mode, plan: plan, runs: runs.result.runs)
    }

    // MARK: Lifecycle

    /// Opening the tab: the cached runs, then a refresh if the last one is stale.
    func appear() async {
        await plans.loadIfNeeded()
        await runs.loadCached()
        await runs.refreshIfStale()
    }

    /// Leaving the screen (another tab, or a pushed detail) cancels the mode and the notice.
    func leave() {
        mode = nil
        plans.clearNotice()
    }

    /// Pull to refresh: the shared runs refresh. The month and selection stay.
    func refresh() async {
        await runs.refresh()
    }

    // MARK: Month and selection

    /// Changing the month resets the selection by the default rule. While
    /// editing the mode stays, so a move can cross months.
    func showPreviousMonth() {
        guard let overview, overview.canGoBack else { return }
        month = overview.month.adding(months: -1)
        if mode == nil { chosenDate = nil }
    }

    func showNextMonth() {
        guard let overview, overview.canGoForward else { return }
        month = overview.month.adding(months: 1)
        if mode == nil { chosenDate = nil }
    }

    /// Idle: selects a day inside the plan (another day clears the notice).
    /// Editing: a valid target applies the edit; any other tap is ignored.
    func tap(_ date: LocalDate) async {
        if let mode {
            guard
                !isApplying,
                let plan = plans.plan,
                let edit = getCalendarMonth.edit(mode, target: date, plan: plan, runs: runs.result.runs)
            else { return }
            await apply(edit)
            return
        }
        select(date)
    }

    /// Days outside the plan cannot be selected.
    func select(_ date: LocalDate) {
        guard mode == nil, overview?.cells.first(where: { $0.date == date })?.isSelectable == true else { return }
        if date != selectedDate { plans.clearNotice() }
        chosenDate = date
    }

    // MARK: Editing

    /// One-tap actions save at once; "another day" and "swap" start a mode.
    func perform(_ action: PlanAction) async {
        guard
            mode == nil, !isApplying, action.isEnabled,
            let overview, let sessionId = overview.selectedSessionId, let plan = plans.plan
        else { return }
        switch action.kind {
        case .moveAnotherDay:
            plans.clearNotice()
            chosenDate = overview.selectedDate
            mode = .moving(sessionId: sessionId)
        case .swap:
            plans.clearNotice()
            chosenDate = overview.selectedDate
            mode = .swapping(sessionId: sessionId)
        case .moveNextDay, .markMissed:
            guard let edit = getCalendarMonth.edit(action, sessionId: sessionId, plan: plan) else { return }
            await apply(edit)
        }
    }

    /// Back to idle on the session being edited, with nothing changed.
    func cancelEdit() {
        guard let mode else { return }
        self.mode = nil
        if let date = plans.plan?.session(id: mode.sessionId)?.date {
            focus(date)
        }
    }

    /// Restores the dates or flag and selects the original day again.
    func undo() async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        if let date = await plans.undo() {
            focus(date)
        }
    }

    /// Hides the failure bar.
    func dismissFailure() {
        plans.clearNotice()
    }

    private func apply(_ edit: PlanEdit) async {
        isApplying = true
        defer { isApplying = false }
        mode = nil
        if let outcome = await plans.apply(edit, runs: runs.result.runs) {
            focus(outcome.focusDate)
        }
    }

    /// Shows the month holding `date` and selects it.
    private func focus(_ date: LocalDate) {
        month = YearMonth(date)
        chosenDate = date
    }
}
