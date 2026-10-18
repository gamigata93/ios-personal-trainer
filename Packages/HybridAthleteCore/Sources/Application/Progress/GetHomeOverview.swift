import Foundation
import Domain

/// Builds the Home screen's content from the plan, the completed runs and the
/// current time, using the Domain progress rules.
public struct GetHomeOverview: Sendable {
    private let clock: any Clock
    private let calendar: Calendar
    private let sleepOverview: GetSleepOverview
    private let recoveryOverview: GetRecoveryOverview

    public init(clock: any Clock, calendar: Calendar, sleepOverview: GetSleepOverview, recoveryOverview: GetRecoveryOverview) {
        self.clock = clock
        self.calendar = calendar
        self.sleepOverview = sleepOverview
        self.recoveryOverview = recoveryOverview
    }

    /// `weekOffset` moves the strip from the current week; `selectedDate` is kept
    /// when it is in the shown week, otherwise the default rule picks a day.
    public func execute(
        plan: TrainingPlan,
        runs: CompletedRunsResult,
        recovery: RecoveryStates = .loading,
        weekOffset: Int = 0,
        selectedDate: LocalDate? = nil
    ) -> HomeOverview {
        let now = clock.now()
        let today = LocalDate(date: now, calendar: calendar)
        let progress = PlanProgress(plan: plan, runs: runs.runs, strength: runs.strength, today: today)
        let raceTitle = HomeFormat.raceTitle(distanceKm: plan.race.distanceKm)

        let shown = progress.stage == .finished ? nil : WeekStripBuilder.week(progress: progress, weekOffset: weekOffset)
        let selected = shown.map { week in
            selectedDate.flatMap { week.contains($0) ? $0 : nil } ?? week.defaultSelection(today: today)
        }

        return HomeOverview(
            header: HomeOverview.Header(
                dateCaption: HomeFormat.longDate(today),
                greeting: HomeFormat.greeting(hour: calendar.component(.hour, from: now))
            ),
            planCard: planCard(progress, raceTitle: raceTitle),
            week: shown.map { week(of: $0, selected: selected, today: today) },
            selectedDate: selected,
            selectedCard: shown.flatMap { week in
                selected.flatMap { date in week.days.first { $0.date == date } }.map { DayCard.make(session: $0.session, status: $0.status, isRaceDay: $0.isRaceDay, raceTitle: raceTitle) }
            },
            strengthCard: shown.flatMap { week in
                selected.flatMap { date in week.days.first { $0.date == date } }.flatMap { StrengthCard.make($0.strength, status: $0.strengthStatus) }
            },
            upNext: progress.nextSession(after: today).map { session in
                HomeOverview.UpNext(
                    sessionID: session.id,
                    caption: "Up next · \(HomeFormat.shortDate(session.date))",
                    type: session.type,
                    name: session.name,
                    meta: HomeFormat.sessionMeta(session)
                )
            },
            lockedLine: ProgressLockedLine.text(runs: runs, now: now, calendar: calendar),
            recovery: RecoveryOverview.make(
                recovery,
                sleepOverview: sleepOverview,
                recoveryOverview: recoveryOverview,
                today: today,
                now: now,
                calendar: calendar
            ),
            completedCount: progress.completedCount,
            dueCount: progress.dueCount
        )
    }

    // MARK: Parts

    private func planCard(_ progress: PlanProgress, raceTitle: String) -> HomeOverview.PlanCard {
        let adherence = progress.adherence
        let percent = adherence.map { Int(($0 * 100).rounded()) }
        let stage = progress.stage
        let days = progress.daysToRace

        let countdownValue: String
        let countdownUnit: String?
        switch stage {
        case .finished:
            countdownValue = "Finished"
            countdownUnit = nil
        case .notStarted, .inProgress:
            countdownValue = days == 0 ? "Race day" : "\(days)"
            countdownUnit = days == 0 ? nil : (days == 1 ? "day to go" : "days to go")
        }

        let pill: HomeOverview.Pill?
        let weekCaption: String?
        let ringCaption: String
        switch stage {
        case .notStarted(let starts):
            let text = "Starts \(HomeFormat.shortDate(starts))"
            pill = HomeOverview.Pill(text: text, isMuted: true)
            weekCaption = nil
            ringCaption = percent == nil ? text : "on plan"
        case .inProgress(let week, let phase):
            pill = HomeOverview.Pill(text: "\(phase.rawValue.capitalized) phase", isMuted: false)
            weekCaption = "Week \(week) of \(progress.plan.weeks.count)"
            ringCaption = "on plan"
        case .finished:
            pill = nil
            weekCaption = nil
            ringCaption = "on plan"
        }

        return HomeOverview.PlanCard(
            raceTitle: raceTitle,
            adherence: adherence,
            ringValue: percent.map { "\($0)%" } ?? "-",
            ringCaption: ringCaption,
            ringAccessibilityLabel: percent.map { "Plan adherence \($0) percent" } ?? "Plan has not started",
            countdownValue: countdownValue,
            countdownUnit: countdownUnit,
            pill: pill,
            weekCaption: weekCaption
        )
    }

    private func week(of shown: ShownWeek, selected: LocalDate?, today: LocalDate) -> HomeOverview.Week {
        HomeOverview.Week(
            index: shown.index,
            rangeLabel: HomeFormat.weekRangeLabel(start: shown.startDate, end: shown.endDate),
            canGoBack: shown.canGoBack,
            canGoForward: shown.canGoForward,
            days: shown.days.map { cell in
                HomeOverview.Day(
                    date: cell.date,
                    weekdayShort: HomeFormat.shortWeekday(cell.weekday),
                    dayNumber: "\(cell.date.day)",
                    isToday: cell.isToday,
                    isSelected: cell.date == selected,
                    sessionType: cell.session?.type,
                    status: cell.status,
                    isRaceDay: cell.isRaceDay,
                    strengthStatus: cell.strengthStatus,
                    accessibilityLabel: accessibilityLabel(cell)
                )
            }
        )
    }

    /// "Wednesday 28 October, Easy run, today".
    private func accessibilityLabel(_ cell: DayCell) -> String {
        HomeFormat.dayAccessibilityLabel(
            date: cell.date, sessionName: cell.session?.name, isRaceDay: cell.isRaceDay, status: cell.status, isToday: cell.isToday,
            strength: cell.strength.flatMap { item in cell.strengthStatus.map { (item.name, $0) } }
        )
    }
}
