import Foundation
import Testing
import Domain

private typealias F = EditPlanFixture

private func violations(_ edit: PlanEdit, plan: TrainingPlan = F.base, runs: [CompletedRun] = F.runs) -> [EditViolation] {
    PlanEditValidator.violations(plan: plan, runs: runs, today: F.today, edit: edit)
}

private func move(_ id: String, from: LocalDate, to: LocalDate) -> PlanEdit {
    .move(sessionId: id, from: from, to: to)
}

private func status(_ id: String, plan: TrainingPlan, runs: [CompletedRun] = F.runs) throws -> SessionStatus {
    let session = try #require(plan.session(id: id))
    return PlanProgress(plan: plan, runs: runs, today: F.today).status(of: session)
}

@Suite("Plan edit rules")
struct PlanEditRulesTests {
    @Test func windowRunsFromTodayToRaceDayMinusTwo() {
        #expect(PlanEditRules.earliestTarget(plan: F.base, today: F.today) == F.day(10, 28))
        #expect(PlanEditRules.earliestTarget(plan: F.base, today: F.day(10, 1)) == F.planStart)
        #expect(PlanEditRules.latestTarget(plan: F.base) == F.day(12, 4))
        #expect(PlanEditRules.hardTypes == [.tempo, .threshold, .intervals, .long])
    }

    @Test func fixtureStatuses() throws {
        for d in [12, 14, 16, 19, 23, 26] { #expect(try status(F.id(10, d), plan: F.base) == .completed) }
        #expect(try status(F.id(10, 21), plan: F.base) == .notRecorded)
        #expect(try status(F.id(10, 28), plan: F.base) == .today)
        #expect(try status(F.id(10, 30), plan: F.base) == .upcoming)
    }
}

@Suite("Plan edit validator")
struct PlanEditValidatorTests {
    let today = F.day(10, 28)

    @Test func moveTargets() {
        let id = F.id(10, 28)
        #expect(violations(move(id, from: today, to: F.day(10, 29))).isEmpty)
        #expect(violations(move(id, from: today, to: F.day(10, 27))) == [.targetBeforeEarliest])
        #expect(violations(move(id, from: today, to: F.day(10, 28))) == [.sameDate])
        #expect(violations(move(id, from: today, to: F.day(10, 30))) == [.targetOccupied])
        #expect(violations(move(id, from: today, to: F.day(12, 5))) == [.targetAfterLatest])
        #expect(violations(move(id, from: today, to: F.day(12, 6))) == [.targetAfterLatest])
        #expect(violations(move(id, from: today, to: F.day(12, 3))).isEmpty)
        #expect(violations(move(id, from: today, to: F.day(12, 4))) == [.targetOccupied])
    }

    @Test func completedSessionCannotMove() {
        #expect(violations(move(F.id(10, 23), from: F.day(10, 23), to: F.day(10, 29))) == [.completed])
    }

    @Test func notRecordedMovesForwardAndKeepsItsId() throws {
        let edit = move(F.id(10, 21), from: F.day(10, 21), to: F.day(10, 29))
        #expect(violations(edit).isEmpty)
        let missed = try #require(PlanEditApplier.apply(.markMissed(sessionId: F.id(10, 21)), to: F.base))
        let moved = try #require(PlanEditApplier.apply(edit, to: missed))
        let session = try #require(moved.session(id: "2026-10-21"))
        #expect(session.date == F.day(10, 29))
        #expect(session.isMissed == false)
        #expect(session.originalDate == F.day(10, 21))
        #expect(moved.session(on: F.day(10, 21)) == nil)
        // Placed in the week holding its new date, still sorted.
        let week3 = try #require(moved.weeks.first { $0.index == 3 })
        #expect(week3.sessions.map(\.id) == ["2026-10-26", "2026-10-28", "2026-10-21", "2026-10-30"])
        #expect(moved.weeks.first { $0.index == 2 }?.sessions.map(\.id) == ["2026-10-19", "2026-10-23"])
    }

    @Test func swapExchangesDatesOnly() throws {
        let edit = PlanEdit.swap(sessionIdA: F.id(10, 28), sessionIdB: F.id(10, 30), dateA: F.day(10, 28), dateB: F.day(10, 30))
        #expect(violations(edit).isEmpty)
        let swapped = try #require(PlanEditApplier.apply(edit, to: F.base))
        let easy = try #require(swapped.session(id: "2026-10-28"))
        let long = try #require(swapped.session(id: "2026-10-30"))
        #expect(easy.date == F.day(10, 30) && easy.type == .easy && easy.distanceKm == 6.5)
        #expect(long.date == F.day(10, 28) && long.type == .long && long.distanceKm == 10)
    }

    @Test func swapNeedsTwoTodayOrUpcomingSessions() {
        func swap(_ a: Int, _ b: Int) -> PlanEdit {
            .swap(sessionIdA: F.id(10, a), sessionIdB: F.id(10, b), dateA: F.day(10, a), dateB: F.day(10, b))
        }
        #expect(violations(swap(28, 21)) == [.notSwappable])
        #expect(violations(swap(28, 26)) == [.notSwappable])
        #expect(violations(swap(28, 28)) == [.notSwappable])
        #expect(violations(.swap(sessionIdA: "nope", sessionIdB: F.id(10, 30), dateA: F.day(10, 1), dateB: F.day(10, 30))) == [.sessionNotFound])
    }

    @Test func markMissed() throws {
        #expect(violations(.markMissed(sessionId: F.id(10, 21))).isEmpty)
        #expect(violations(.markMissed(sessionId: F.id(10, 28))).isEmpty)
        #expect(violations(.markMissed(sessionId: F.id(10, 30))) == [.cannotMarkMissed])
        #expect(violations(.markMissed(sessionId: F.id(10, 23))) == [.completed])
        let missed = try #require(PlanEditApplier.apply(.markMissed(sessionId: F.id(10, 21)), to: F.base))
        #expect(violations(.markMissed(sessionId: F.id(10, 21)), plan: missed) == [.cannotMarkMissed])
        #expect(try status(F.id(10, 21), plan: missed) == .missed)
    }

    @Test func aMissedSessionWithAMatchingRunIsCompleted() throws {
        let missed = try #require(PlanEditApplier.apply(.markMissed(sessionId: F.id(10, 28)), to: F.base))
        #expect(try status(F.id(10, 28), plan: missed) == .missed)
        #expect(try status(F.id(10, 28), plan: missed, runs: F.runs + [F.run(F.day(10, 28), 6.5)]) == .completed)
    }

    @Test func unknownSession() {
        #expect(violations(move("2026-10-29", from: F.day(10, 29), to: F.day(10, 31))) == [.sessionNotFound])
        #expect(violations(.markMissed(sessionId: "x")) == [.sessionNotFound])
    }
}

@Suite("Plan change")
struct PlanChangeTests {
    @Test func inverseRestoresAMoveOfAMissedSession() throws {
        let missed = try #require(PlanEditApplier.apply(.markMissed(sessionId: F.id(10, 21)), to: F.base))
        let edit = move(F.id(10, 21), from: F.day(10, 21), to: F.day(10, 29))
        let change = try #require(PlanChange.make(edit, current: PlanEditApplier.placements(of: missed)))
        #expect(change.before == [SessionPlacement(sessionId: "2026-10-21", date: F.day(10, 21), isMissed: true)])
        #expect(change.after == [SessionPlacement(sessionId: "2026-10-21", date: F.day(10, 29), isMissed: false)])
        let undone = PlanEditApplier.apply(change.inverse, to: PlanEditApplier.apply(change, to: missed))
        #expect(undone == missed)
    }

    @Test func staleEditsMakeNoChange() {
        let placements = PlanEditApplier.placements(of: F.base)
        #expect(PlanChange.make(move(F.id(10, 28), from: F.day(10, 27), to: F.day(10, 29)), current: placements) == nil)
        #expect(PlanChange.make(
            .swap(sessionIdA: F.id(10, 28), sessionIdB: F.id(10, 30), dateA: F.day(10, 28), dateB: F.day(10, 31)), current: placements
        ) == nil)
    }

    @Test func swapRoundTrip() throws {
        let edit = PlanEdit.swap(sessionIdA: F.id(10, 28), sessionIdB: F.id(10, 30), dateA: F.day(10, 28), dateB: F.day(10, 30))
        let change = try #require(PlanChange.make(edit, current: PlanEditApplier.placements(of: F.base)))
        #expect(PlanEditApplier.apply(change.inverse, to: PlanEditApplier.apply(change, to: F.base)) == F.base)
    }
}

@Suite("Plan actions")
struct PlanActionsTests {
    private func actions(_ id: String, plan: TrainingPlan = F.base) throws -> [PlanAction] {
        PlanActions.available(session: try #require(plan.session(id: id)), plan: plan, runs: F.runs, today: F.today)
    }

    @Test func today() throws {
        let list = try actions(F.id(10, 28))
        #expect(list.map(\.kind) == [.moveNextDay, .moveAnotherDay, .swap, .markMissed])
        #expect(list[0] == PlanAction(kind: .moveNextDay, label: "Move to next day", hint: "Thu 29 Oct is free", isEnabled: true, target: F.day(10, 29)))
        #expect(list[1].label == "Move to another day\u{2026}" && list[1].hint == "Pick any free day" && list[1].isEnabled)
        #expect(list[2].label == "Swap with another session\u{2026}" && list[2].hint == "Trade places with an upcoming session" && list[2].isEnabled)
        #expect(list[3].label == "Mark as missed" && list[3].hint == "Skip today's session" && list[3].isEnabled)
    }

    @Test func upcoming() throws {
        let list = try actions(F.id(10, 30))
        #expect(list.map(\.kind) == [.moveNextDay, .moveAnotherDay, .swap])
        #expect(list[0].target == F.day(10, 31) && list[0].isEnabled && list[0].hint == "Sat 31 Oct is free")
    }

    @Test func notRecorded() throws {
        let list = try actions(F.id(10, 21))
        #expect(list.map(\.kind) == [.moveAnotherDay, .markMissed])
        #expect(list.map(\.label) == ["Move forward to another day\u{2026}", "Mark as missed"])
        #expect(list[1].hint == "Acknowledge it and move on")
    }

    @Test func missedOnlyMovesForward() throws {
        let missed = try #require(PlanEditApplier.apply(.markMissed(sessionId: F.id(10, 21)), to: F.base))
        #expect(try actions(F.id(10, 21), plan: missed).map(\.label) == ["Move forward to another day\u{2026}"])
    }

    @Test func completedHasNone() throws {
        #expect(try actions(F.id(10, 23)).isEmpty)
    }

    @Test func nextDayOccupiedOrTooCloseToRace() throws {
        let busy = F.plan(extra: [F.day(10, 29)])
        let first = try #require(try actions(F.id(10, 28), plan: busy).first)
        #expect(first.kind == .moveNextDay && !first.isEnabled && first.hint == "Thu 29 Oct already has a session")
        let last = try #require(try actions(F.id(12, 4)).first)
        #expect(last.kind == .moveNextDay && !last.isEnabled && last.hint == "Sat 5 Dec is too close to race day")
    }

    @Test func swapDisabledWithoutAnotherSwappableSession() throws {
        // Only 3 Dec (moved there) and nothing else upcoming: build a plan whose only upcoming session is 4 Dec.
        let plan = F.base.replacingSessions(F.base.sessions.filter { $0.date < F.today || $0.date == F.day(12, 4) })
        let list = try actions(F.id(12, 4), plan: plan)
        #expect(list.first { $0.kind == .swap }?.isEnabled == false)
    }

    @Test func targetSets() {
        let moves = PlanEditTargets.moveTargets(sessionId: F.id(10, 28), plan: F.base, runs: F.runs, today: F.today)
        #expect(moves.contains(F.day(10, 29)) && moves.contains(F.day(12, 3)) && moves.contains(F.day(11, 1)))
        #expect(!moves.contains(F.day(10, 28)) && !moves.contains(F.day(10, 30)) && !moves.contains(F.day(12, 5)) && !moves.contains(F.day(10, 27)))
        let swaps = PlanEditTargets.swapTargets(sessionId: F.id(10, 28), plan: F.base, runs: F.runs, today: F.today)
        #expect(swaps.contains(F.day(10, 30)) && swaps.contains(F.day(12, 4)))
        #expect(!swaps.contains(F.day(10, 28)) && !swaps.contains(F.day(10, 26)) && !swaps.contains(F.day(10, 21)))
    }
}

@Suite("Hard days heads-up and notices")
struct HardDaysAndNoticeTests {
    @Test func thresholdNextToLongRunWarns() throws {
        let edit = move(F.id(11, 2), from: F.day(11, 2), to: F.day(10, 31))
        let plan = try #require(PlanEditApplier.apply(edit, to: F.base))
        #expect(HardDaysWarning.applies(plan: plan, editedDates: [F.day(10, 31)]))
    }

    @Test func easyNextToLongRunDoesNot() throws {
        let plan = try #require(PlanEditApplier.apply(move(F.id(10, 28), from: F.day(10, 28), to: F.day(10, 29)), to: F.base))
        #expect(!HardDaysWarning.applies(plan: plan, editedDates: [F.day(10, 29)]))
    }

    @Test func swapWithoutHardNeighborsDoesNot() throws {
        let edit = PlanEdit.swap(sessionIdA: F.id(10, 28), sessionIdB: F.id(10, 30), dateA: F.day(10, 28), dateB: F.day(10, 30))
        let plan = try #require(PlanEditApplier.apply(edit, to: F.base))
        #expect(!HardDaysWarning.applies(plan: plan, editedDates: [F.day(10, 28), F.day(10, 30)]))
    }

    @Test func noticeTexts() {
        #expect(PlanEditFormat.notice(for: move(F.id(10, 28), from: F.day(10, 28), to: F.day(10, 29)), in: F.base) == "Moved Easy run to Thu 29 Oct.")
        #expect(PlanEditFormat.notice(
            for: .swap(sessionIdA: F.id(10, 28), sessionIdB: F.id(10, 30), dateA: F.day(10, 28), dateB: F.day(10, 30)), in: F.base
        ) == "Swapped: Easy run is now on Fri 30 Oct, Long run on Wed 28 Oct.")
        #expect(PlanEditFormat.notice(for: .markMissed(sessionId: F.id(10, 21)), in: F.base) == "Marked Easy run as missed.")
        #expect(PlanEditFormat.headsUp == "Heads-up: two hard sessions on back-to-back days.")
    }

    @Test func movedFromChip() throws {
        let plan = try #require(PlanEditApplier.apply(move(F.id(10, 28), from: F.day(10, 28), to: F.day(10, 29)), to: F.base))
        #expect(PlanEditFormat.movedFrom(try #require(plan.session(id: F.id(10, 28)))) == "Moved from Wed 28 Oct")
        #expect(PlanEditFormat.movedFrom(try #require(plan.session(id: F.id(10, 30)))) == nil)
    }
}

@Suite("Progress with edits")
struct ProgressWithEditsTests {
    @Test func missedCountsAsDueNotCompleted() throws {
        let missed = try #require(PlanEditApplier.apply(.markMissed(sessionId: F.id(10, 21)), to: F.base))
        let progress = PlanProgress(plan: missed, runs: F.runs, today: F.today)
        #expect(progress.completedCount == 6)
        #expect(progress.dueCount == 7)
    }

    @Test func movingForwardLeavesTheDueCount() throws {
        let moved = try #require(PlanEditApplier.apply(move(F.id(10, 21), from: F.day(10, 21), to: F.day(10, 29)), to: F.base))
        let progress = PlanProgress(plan: moved, runs: F.runs, today: F.today)
        #expect(progress.completedCount == 6)
        #expect(progress.dueCount == 6)
        #expect(progress.adherence == 1)
    }

    @Test func todayMarkedMissedIsDue() throws {
        let missed = try #require(PlanEditApplier.apply(.markMissed(sessionId: F.id(10, 28)), to: F.base))
        #expect(PlanProgress(plan: missed, runs: F.runs, today: F.today).dueCount == 8)
    }

    @Test func upNextSkipsMissedSessions() {
        let thirtieth = F.base.session(id: F.id(10, 30))?.placed(on: F.day(10, 30), isMissed: true)
        let plan = F.base.replacingSessions(F.base.sessions.map { $0.id == F.id(10, 30) ? (thirtieth ?? $0) : $0 })
        #expect(PlanProgress(plan: plan, runs: F.runs, today: F.today).nextSession(after: F.today)?.id == F.id(11, 2))
    }

    @Test func calendarCellsFollowTheCurrentDate() throws {
        let moved = try #require(PlanEditApplier.apply(move(F.id(10, 28), from: F.day(10, 28), to: F.day(10, 29)), to: F.base))
        let month = CalendarMonthBuilder.month(YearMonth(year: 2026, month: 10), plan: moved, runs: F.runs, today: F.today)
        #expect(month.cell(on: F.day(10, 28))?.session == nil)
        #expect(month.cell(on: F.day(10, 29))?.session?.id == "2026-10-28")
        #expect(month.cell(on: F.day(10, 29))?.status == .upcoming)
    }

    @Test func legacyJSONDecodesWithOriginalDateAndNotMissed() throws {
        let json = #"{"id":"2026-10-28","date":"2026-10-28","type":"easy","name":"Easy run","distanceKm":6.5,"effort":"Easy","segments":[]}"#
        let session = try JSONDecoder().decode(PlannedSession.self, from: Data(json.utf8))
        #expect(session.originalDate == F.day(10, 28) && session.isMissed == false && session.id == "2026-10-28")
    }
}
