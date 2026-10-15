import Foundation
import Testing
import Domain

struct PlanValidatorTests {
    // Plan start Mon 12 Oct 2026, 10 km race on Sun 8 Nov (4 weeks), Tue and Sun.
    private let request = PlanRequest(
        race: RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: LocalDate(year: 2026, month: 11, day: 8), trainingDays: [.tuesday, .sunday]),
        fitness: FitnessSummary(weeklyKm: 10, longestRunKm: 5, avgPaceSecPerKm: nil),
        today: LocalDate(year: 2026, month: 10, day: 9),
        planKind: .tenK,
        source: .custom
    )

    private func session(_ month: Int, _ day: Int, _ type: SessionType = .easy, km: Double) -> PlannedSession {
        PlannedSession(date: LocalDate(year: 2026, month: month, day: day), type: type, name: "Run", distanceKm: km, estimatedMinutes: nil, effort: "Easy", segments: [], note: nil)
    }

    private func week(_ index: Int, _ phase: PlanPhase, _ sessions: [PlannedSession]) -> PlanWeek {
        PlanWeek(index: index, startDate: LocalDate(year: 2026, month: 10, day: 12).adding(days: (index - 1) * 7), phase: phase, targetKm: 0, sessions: sessions)
    }

    /// Totals 11, 12, 13, 4: each within 125% of the larger of the two before.
    private var validWeeks: [PlanWeek] {
        [
            week(1, .base, [session(10, 13, .tempo, km: 5), session(10, 18, .long, km: 6)]),
            week(2, .build, [session(10, 20, .threshold, km: 5), session(10, 25, .long, km: 7)]),
            week(3, .peak, [session(10, 27, .intervals, km: 6), session(11, 1, .long, km: 7)]),
            week(4, .taper, [session(11, 3, .tempo, km: 4)]),
        ]
    }

    private func plan(_ weeks: [PlanWeek]) -> TrainingPlan {
        TrainingPlan(id: "p", createdAt: Date(timeIntervalSinceReferenceDate: 0), generatedBy: "test", planKind: .tenK,
                     race: request.race, planStart: request.planStart, weeks: weeks)
    }

    private func violations(_ weeks: [PlanWeek]) -> [PlanViolation] {
        PlanValidator.violations(plan(weeks), request: request)
    }

    private func replacing(week index: Int, with sessions: [PlannedSession], phase: PlanPhase? = nil) -> [PlanWeek] {
        var weeks = validWeeks
        weeks[index] = week(index + 1, phase ?? weeks[index].phase, sessions)
        return weeks
    }

    @Test func aValidPlanPasses() {
        #expect(violations(validWeeks).isEmpty)
    }

    @Test func rejectsAnEmptyPlan() {
        #expect(violations([]).contains(.noSessions))
    }

    @Test func rejectsANonChosenWeekday() {
        let weeks = replacing(week: 0, with: [session(10, 14, .tempo, km: 5), session(10, 18, .long, km: 6)]) // Wednesday
        #expect(violations(weeks).contains(.sessionOnRestDay(LocalDate(year: 2026, month: 10, day: 14))))
    }

    @Test func rejectsRaceDayAndTheDayBefore() {
        var weeks = validWeeks
        weeks[3] = week(4, .taper, [session(11, 3, .tempo, km: 4), session(11, 8, km: 3)])
        #expect(violations(weeks).contains(.sessionOutsideWindow(LocalDate(year: 2026, month: 11, day: 8))))

        let saturdayRequest = PlanRequest(
            race: RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: request.race.raceDate, trainingDays: [.tuesday, .saturday, .sunday]),
            fitness: request.fitness, today: request.today, planKind: .tenK, source: .custom
        )
        weeks[3] = week(4, .taper, [session(11, 3, .tempo, km: 4), session(11, 7, km: 3)])
        #expect(PlanValidator.violations(plan(weeks), request: saturdayRequest).contains(.sessionOutsideWindow(LocalDate(year: 2026, month: 11, day: 7))))
    }

    @Test func rejectsASessionBeforeThePlanStarts() {
        var weeks = validWeeks
        weeks[0] = PlanWeek(index: 1, startDate: request.planStart, phase: .base, targetKm: 0,
                            sessions: [session(10, 11, km: 5), session(10, 18, .long, km: 6)]) // Sun 11 Oct
        #expect(violations(weeks).contains(.sessionOutsideWindow(LocalDate(year: 2026, month: 10, day: 11))))
    }

    @Test(arguments: [0.0, -3, 61])
    func rejectsBadDistances(km: Double) {
        let weeks = replacing(week: 0, with: [session(10, 13, .tempo, km: km), session(10, 18, .long, km: 6)])
        #expect(violations(weeks).contains(.badDistance(LocalDate(year: 2026, month: 10, day: 13))))
    }

    @Test func rejectsALongRunOverTheCap() {
        // 10K cap is 18 km.
        let weeks = replacing(week: 0, with: [session(10, 13, km: 1), session(10, 18, .long, km: 18.5)])
        #expect(violations(weeks).contains(.longRunOverCap(LocalDate(year: 2026, month: 10, day: 18))))
    }

    @Test func rejectsTwoSessionsOnOneDay() {
        let weeks = replacing(week: 0, with: [session(10, 13, km: 3), session(10, 13, km: 2), session(10, 18, .long, km: 6)])
        #expect(violations(weeks).contains(.twoSessionsOnOneDay(LocalDate(year: 2026, month: 10, day: 13))))
        #expect(violations(weeks).contains(.tooManySessionsInWeek(week: 1)))
    }

    @Test func rejectsAWeekThatGrowsTooFast() {
        // Week 2 at 16 km against max(11, 10) x 1.25 = 13.75.
        let weeks = replacing(week: 1, with: [session(10, 20, .threshold, km: 7), session(10, 25, .long, km: 9)])
        #expect(violations(weeks).contains(.weekGrowsTooFast(week: 2)))
    }

    @Test func firstWeekComparesWithTheBaselineOrTen() {
        // 13 km in week 1 against max(10, 10) x 1.25 = 12.5.
        let weeks = replacing(week: 0, with: [session(10, 13, .tempo, km: 6), session(10, 18, .long, km: 7)])
        #expect(violations(weeks).contains(.weekGrowsTooFast(week: 1)))
    }

    @Test func rejectsATaperThatIsNotLast() {
        var weeks = validWeeks
        weeks[2] = week(3, .taper, weeks[2].sessions)
        weeks[3] = week(4, .peak, weeks[3].sessions)
        let found = violations(weeks)
        #expect(found.contains(.phasesOutOfOrder(week: 4)))
        #expect(found.contains(.lastWeekNotTaper))
    }
}
