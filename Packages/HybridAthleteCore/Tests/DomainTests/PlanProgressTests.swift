import Foundation
import Testing
@testable import Domain

struct PlanProgressTests {
    private typealias F = PlanFixtures
    private let plan = F.twoWeeks

    private func progress(today: LocalDate, runs: [CompletedRun] = []) -> PlanProgress {
        PlanProgress(plan: plan, runs: runs, today: today)
    }

    @Test func nothingDueGivesNoAdherence() {
        // Mon 12 Oct with today's session not done yet: due = 0, so nil, not 0%.
        let state = progress(today: F.day(10, 12))
        #expect(state.dueCount == 0)
        #expect(state.adherence == nil)
    }

    @Test func todaysSessionCountsOnlyOnceCompleted() {
        let open = progress(today: F.day(10, 14), runs: [F.run(F.day(10, 12), km: 5)])
        #expect(open.dueCount == 1)
        #expect(open.adherence == 1)

        let done = progress(today: F.day(10, 14), runs: [F.run(F.day(10, 12), km: 5), F.run(F.day(10, 14), km: 6)])
        #expect(done.dueCount == 2)
        #expect(done.completedCount == 2)
    }

    @Test func adherenceIsCompletedOverDue() {
        // Due on Sun 18 Oct: 12, 14, 17. Only 14 done -> 1/3.
        let state = progress(today: F.day(10, 18), runs: [F.run(F.day(10, 14), km: 6)])
        #expect(state.completedCount == 1)
        #expect(state.dueCount == 3)
        #expect(state.adherence == 1.0 / 3.0)
    }

    @Test func stageAndWeekFollowToday() {
        #expect(progress(today: F.day(10, 11)).stage == .notStarted(starts: F.day(10, 12)))
        #expect(progress(today: F.day(10, 11)).currentWeekIndex == nil)
        #expect(progress(today: F.day(10, 18)).stage == .inProgress(week: 1, phase: .base))
        #expect(progress(today: F.day(10, 19)).stage == .inProgress(week: 2, phase: .taper))
        #expect(progress(today: F.day(10, 25)).stage == .inProgress(week: 2, phase: .taper))
        #expect(progress(today: F.day(10, 26)).stage == .finished)
        #expect(progress(today: F.day(10, 26)).currentWeekIndex == nil)
    }

    @Test func daysToRaceIsNeverNegative() {
        #expect(progress(today: F.day(10, 11)).daysToRace == 14)
        #expect(progress(today: F.day(10, 25)).daysToRace == 0)
        #expect(progress(today: F.day(11, 2)).daysToRace == 0)
    }

    @Test func nextSessionIsStrictlyAfterTheDate() {
        #expect(progress(today: F.day(10, 14)).nextSession(after: F.day(10, 14))?.date == F.day(10, 17))
        #expect(progress(today: F.day(10, 22)).nextSession(after: F.day(10, 22)) == nil)
    }

    // MARK: Week strip

    @Test func theStripShowsTheWeekHoldingToday() throws {
        let week = try #require(WeekStripBuilder.week(progress: progress(today: F.day(10, 14)), weekOffset: 0))
        #expect(week.index == 1)
        #expect(week.days.map(\.date) == (0..<7).map { F.day(10, 12 + $0) })
        #expect(week.days.filter(\.isToday).map(\.date) == [F.day(10, 14)])
        #expect(week.days[1].session == nil)
        #expect(week.days[2].status == .today)
        #expect(week.days[5].status == .upcoming)
    }

    @Test func weekOffsetsAreClampedToThePlan() throws {
        let state = progress(today: F.day(10, 14))
        let back = try #require(WeekStripBuilder.week(progress: state, weekOffset: -3))
        #expect(back.index == 1)
        #expect(!back.canGoBack)
        #expect(back.canGoForward)
        let forward = try #require(WeekStripBuilder.week(progress: state, weekOffset: 4))
        #expect(forward.index == 2)
        #expect(forward.canGoBack)
        #expect(!forward.canGoForward)
        #expect(forward.days[6].isRaceDay)
    }

    @Test func beforeTheStartTheStripShowsWeekOne() throws {
        let week = try #require(WeekStripBuilder.week(progress: progress(today: F.day(10, 10)), weekOffset: 0))
        #expect(week.index == 1)
        #expect(!week.days.contains { $0.isToday })
        #expect(week.defaultSelection(today: F.day(10, 10)) == F.day(10, 12))
    }

    @Test func defaultSelectionIsTodayOrTheFirstSessionDay() throws {
        let state = progress(today: F.day(10, 13))
        let current = try #require(WeekStripBuilder.week(progress: state, weekOffset: 0))
        #expect(current.defaultSelection(today: F.day(10, 13)) == F.day(10, 13))
        let next = try #require(WeekStripBuilder.week(progress: state, weekOffset: 1))
        #expect(next.defaultSelection(today: F.day(10, 13)) == F.day(10, 20))
    }
}
