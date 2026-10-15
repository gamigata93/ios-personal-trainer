import Foundation
import Testing
import Application
import Domain

private typealias F = EditPlanFixture

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
}()

/// 09:00 UTC on Wed 28 Oct 2026.
private let todayClock = FakeClock(utc.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 9)) ?? .distantPast)

@Suite("Apply and undo plan edits")
struct PlanEditUseCaseTests {
    private func make(_ plan: TrainingPlan? = F.base) -> (FakePlanRepository, ApplyPlanEdit, UndoPlanEdit) {
        let repository = FakePlanRepository(plan: plan)
        return (repository, ApplyPlanEdit(plans: repository, clock: todayClock, calendar: utc), UndoPlanEdit(plans: repository))
    }

    @Test func moveSavesAndWordsTheNotice() async throws {
        let (repository, apply, _) = make()
        let outcome = try await apply.execute(.move(sessionId: F.id(10, 28), from: F.day(10, 28), to: F.day(10, 29)), runs: F.runs)
        #expect(outcome.notice == "Moved Easy run to Thu 29 Oct.")
        #expect(outcome.headsUp == nil)
        #expect(outcome.focusDate == F.day(10, 29))
        #expect(outcome.undoFocusDate == F.day(10, 28))
        #expect(await repository.plan?.session(id: F.id(10, 28))?.date == F.day(10, 29))
        #expect(await repository.edits.count == 1)
    }

    @Test func swapNotice() async throws {
        let (_, apply, _) = make()
        let outcome = try await apply.execute(
            .swap(sessionIdA: F.id(10, 30), sessionIdB: F.id(10, 28), dateA: F.day(10, 30), dateB: F.day(10, 28)), runs: F.runs
        )
        #expect(outcome.notice == "Swapped: Long run is now on Wed 28 Oct, Easy run on Fri 30 Oct.")
        #expect(outcome.focusDate == F.day(10, 28))
        #expect(outcome.undoFocusDate == F.day(10, 30))
    }

    @Test func hardDaysHeadsUp() async throws {
        let (_, apply, _) = make()
        let outcome = try await apply.execute(.move(sessionId: F.id(11, 2), from: F.day(11, 2), to: F.day(10, 31)), runs: F.runs)
        #expect(outcome.headsUp == "Heads-up: two hard sessions on back-to-back days.")
    }

    @Test func markMissedNotice() async throws {
        let (repository, apply, _) = make()
        let outcome = try await apply.execute(.markMissed(sessionId: F.id(10, 21)), runs: F.runs)
        #expect(outcome.notice == "Marked Easy run as missed.")
        #expect(outcome.focusDate == F.day(10, 21) && outcome.undoFocusDate == F.day(10, 21))
        #expect(await repository.plan?.session(id: F.id(10, 21))?.isMissed == true)
    }

    @Test func violationSavesNothing() async {
        let (repository, apply, _) = make()
        await #expect(throws: PlanEditError.invalid([.targetOccupied])) {
            try await apply.execute(.move(sessionId: F.id(10, 28), from: F.day(10, 28), to: F.day(10, 30)), runs: F.runs)
        }
        await #expect(throws: PlanEditError.invalid([.completed])) {
            try await apply.execute(.markMissed(sessionId: F.id(10, 23)), runs: F.runs)
        }
        #expect(await repository.edits.isEmpty)
        #expect(await repository.plan == F.base)
    }

    @Test func staleAndFailedSaves() async {
        let (repository, apply, _) = make()
        await repository.setEditFailure(PlanRepositoryError.stalePlan)
        await #expect(throws: PlanEditError.stalePlan) {
            try await apply.execute(.move(sessionId: F.id(10, 28), from: F.day(10, 28), to: F.day(10, 29)), runs: F.runs)
        }
        await repository.setEditFailure(FakeStorageError())
        await #expect(throws: PlanEditError.saveFailed) {
            try await apply.execute(.move(sessionId: F.id(10, 28), from: F.day(10, 28), to: F.day(10, 29)), runs: F.runs)
        }
        #expect(await repository.plan == F.base)
    }

    @Test func noPlan() async {
        let (_, apply, undo) = make(nil)
        await #expect(throws: PlanEditError.noActivePlan) {
            try await apply.execute(.markMissed(sessionId: F.id(10, 21)), runs: F.runs)
        }
        await #expect(throws: PlanEditError.noActivePlan) { try await undo.execute(editId: 1) }
    }

    @Test func undoRestoresAndOnlyOnce() async throws {
        let (repository, apply, undo) = make()
        let outcome = try await apply.execute(.move(sessionId: F.id(10, 28), from: F.day(10, 28), to: F.day(10, 29)), runs: F.runs)
        try await undo.execute(editId: outcome.receipt.editId)
        #expect(await repository.plan == F.base)
        await #expect(throws: PlanEditError.cannotUndo) { try await undo.execute(editId: outcome.receipt.editId) }
    }
}

@Suite("Calendar edit mode")
struct CalendarEditModeTests {
    private let use = GetCalendarMonth(clock: todayClock, calendar: utc)
    private let october = YearMonth(year: 2026, month: 10)
    private let runs = CompletedRunsResult(runs: F.runs, asOf: nil, source: .fresh)

    @Test func idleShowsTheSelectedSessionsActions() {
        let month = use.execute(plan: F.base, runs: runs, month: october, selected: F.day(10, 28))
        #expect(month.selectedSessionId == F.id(10, 28))
        #expect(month.actions.map(\.kind) == [.moveNextDay, .moveAnotherDay, .swap, .markMissed])
        #expect(month.banner == nil)
        #expect(month.cells.allSatisfy { $0.editRole == nil })
        #expect(use.execute(plan: F.base, runs: runs, month: october, selected: F.day(10, 23)).actions.isEmpty)
        #expect(use.execute(plan: F.base, runs: runs, month: october, selected: F.day(10, 29)).actions.isEmpty)
    }

    @Test func movingMarksTargetsAndTheSource() throws {
        let month = use.execute(plan: F.base, runs: runs, month: october, selected: F.day(10, 28), mode: .moving(sessionId: F.id(10, 28)))
        #expect(month.actions.isEmpty)
        #expect(month.banner?.title == "Move session")
        #expect(month.banner?.text == "Moving Easy run. Tap a free day, today or later.")
        func cell(_ d: Int) throws -> CalendarMonthOverview.Cell { try #require(month.cells.first { $0.date == F.day(10, d) }) }
        #expect(try cell(28).editRole == .source)
        #expect(try cell(29).editRole == .target)
        #expect(try cell(31).editRole == .target)
        #expect(try cell(30).editRole == .inactive)
        #expect(try cell(27).editRole == .inactive)
        #expect(try cell(29).accessibilityLabel == "Thursday 29 October, free day, double tap to move Easy run here")
    }

    @Test func swappingMarksOtherUpcomingSessions() throws {
        let month = use.execute(plan: F.base, runs: runs, month: october, selected: F.day(10, 30), mode: .swapping(sessionId: F.id(10, 30)))
        #expect(month.banner?.text == "Swapping Long run. Tap an upcoming session to trade places.")
        #expect(month.cells.filter { $0.editRole == .target }.map(\.date) == [F.day(10, 28)])
        #expect(month.cells.first { $0.date == F.day(10, 30) }?.editRole == .source)
    }

    @Test func editsFromTaps() throws {
        let moving = CalendarEditMode.moving(sessionId: F.id(10, 28))
        #expect(use.edit(moving, target: F.day(10, 29), plan: F.base, runs: F.runs) == .move(sessionId: F.id(10, 28), from: F.day(10, 28), to: F.day(10, 29)))
        #expect(use.edit(moving, target: F.day(10, 30), plan: F.base, runs: F.runs) == nil)
        let swapping = CalendarEditMode.swapping(sessionId: F.id(10, 30))
        #expect(use.edit(swapping, target: F.day(10, 28), plan: F.base, runs: F.runs)
            == .swap(sessionIdA: F.id(10, 30), sessionIdB: F.id(10, 28), dateA: F.day(10, 30), dateB: F.day(10, 28)))
        let next = try #require(use.execute(plan: F.base, runs: runs, month: october, selected: F.day(10, 28)).actions.first)
        #expect(use.edit(next, sessionId: F.id(10, 28), plan: F.base) == .move(sessionId: F.id(10, 28), from: F.day(10, 28), to: F.day(10, 29)))
    }

    @Test func movedAndMissedOnTheCardAndDetail() async throws {
        let repository = FakePlanRepository(plan: F.base)
        let apply = ApplyPlanEdit(plans: repository, clock: todayClock, calendar: utc)
        _ = try await apply.execute(.move(sessionId: F.id(10, 28), from: F.day(10, 28), to: F.day(10, 29)), runs: F.runs)
        _ = try await apply.execute(.markMissed(sessionId: F.id(10, 21)), runs: F.runs)
        let plan = try #require(await repository.plan)
        let month = use.execute(plan: plan, runs: runs, month: october, selected: F.day(10, 29))
        guard case .session(let card) = month.dayCard else { Issue.record("no session card"); return }
        #expect(card.movedFrom == "Moved from Wed 28 Oct")
        #expect(card.sessionID == F.id(10, 28))
        let missedMonth = use.execute(plan: plan, runs: runs, month: october, selected: F.day(10, 21))
        guard case .session(let missed) = missedMonth.dayCard else { Issue.record("no session card"); return }
        #expect(missed.status == .missed && missed.statusText == "Missed")
        #expect(missedMonth.cells.first { $0.date == F.day(10, 21) }?.accessibilityLabel == "Wednesday 21 October, Easy run, missed")

        let detail = try #require(GetSessionDetail(clock: todayClock, calendar: utc).execute(plan: plan, runs: F.runs, sessionID: F.id(10, 21)))
        #expect(detail.result == .missed)
        #expect(detail.statusText == "Missed")
        let moved = try #require(GetSessionDetail(clock: todayClock, calendar: utc).execute(plan: plan, runs: F.runs, sessionID: F.id(10, 28)))
        #expect(moved.movedFrom == "Moved from Wed 28 Oct")
        #expect(moved.dateText == "Thursday, 29 October")
    }
}
