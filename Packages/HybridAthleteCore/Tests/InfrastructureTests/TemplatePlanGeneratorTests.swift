import Foundation
import Testing
import Domain
@testable import Infrastructure

struct TemplatePlanGeneratorTests {
    /// Fri 9 Oct 2026.
    private let today = LocalDate(year: 2026, month: 10, day: 9)

    private func request(
        distanceKm: Double = 10,
        gain: Double = 0,
        race: LocalDate = LocalDate(year: 2026, month: 12, day: 6),
        days: Set<Weekday> = [.tuesday, .thursday, .sunday],
        weeklyKm: Double = 17.69,
        pace: Double? = 364
    ) -> PlanRequest {
        PlanRequest(
            race: RaceSetup(distanceKm: distanceKm, elevationGainM: gain, raceDate: race, trainingDays: days),
            fitness: FitnessSummary(weeklyKm: weeklyKm, longestRunKm: 17, avgPaceSecPerKm: pace),
            today: today,
            planKind: PlanKind.from(distanceKm: distanceKm),
            source: .custom
        )
    }

    private func plan(_ request: PlanRequest) -> TrainingPlan {
        TemplatePlanGenerator.plan(for: request)
    }

    private func summary(_ week: PlanWeek) -> [String] {
        week.sessions.map { "\($0.date.weekday.letter)\($0.date.weekday == .thursday ? "h" : "") \($0.type.rawValue) \($0.distanceKm)" }
    }

    // MARK: Worked scenario

    @Test func startsOnTheNextMondayWithEightWeeks() {
        let result = plan(request())
        #expect(result.planStart == LocalDate(year: 2026, month: 10, day: 12))
        #expect(result.weeks.count == 8)
        #expect(result.weeks.map(\.phase) == [.base, .base, .base, .build, .build, .build, .peak, .taper])
        #expect(result.generatedBy == "template-v1")
    }

    @Test func weeklyTargetsMatchTheHandCalculation() {
        // L: 17.69, 19.459, 21.405, [recovery 0.8 x 21.405 = 17.12], 25.90, 28.49, 31.34; taper 0.6 x 31.34 = 18.8.
        #expect(plan(request()).weeks.map(\.targetKm) == [17.5, 19.5, 21.5, 17.0, 26.0, 28.5, 31.5, 19.0])
    }

    @Test func weekOne() {
        let week = plan(request()).weeks[0]
        #expect(summary(week) == ["T tempo 4.5", "Th easy 6.0", "S long 7.0"])
        #expect(week.sessions.map(\.estimatedMinutes) == [25, 35, 40])
        #expect(week.sessions[0].effort == "Comfortably hard")
    }

    @Test func weekFourIsARecoveryWeekWithThreshold() throws {
        let week = plan(request()).weeks[3]
        #expect(summary(week) == ["T threshold 4.5", "Th easy 5.5", "S long 7.0"])
        let threshold = week.sessions[0]
        // Under 6 km: warm-up and cool-down 1.0 each, main 2.5, reps = clamp(round(1.39), 2, 5) = 2.
        #expect(threshold.segments.map(\.distanceKm) == [1.0, 2.5, 1.0])
        #expect(threshold.segments[1].detail == "2 x 8 min at threshold, 90 s jog recovery")
    }

    @Test func weekSevenIsPeakWithIntervals() {
        let week = plan(request()).weeks[6]
        #expect(summary(week) == ["T intervals 8.5", "Th easy 10.5", "S long 12.5"])
        let intervals = week.sessions[0]
        // 8.5 km: warm-up and cool-down 1.5 each, main 5.5, reps = round(4.58) = 5.
        #expect(intervals.segments.map(\.distanceKm) == [1.5, 5.5, 1.5])
        #expect(intervals.segments[1].detail == "5 x 800 m, 400 m jog")
        #expect(week.sessions[2].segments[0].detail == "Steady, last 2 km at moderate effort")
    }

    @Test func raceWeekHasNoLongRunAndCapsSessions() {
        let week = plan(request()).weeks[7]
        // Both capped at 0.75 x 10 km; Sunday is race day.
        #expect(summary(week) == ["T tempo 7.5", "Th easy 7.5"])
        #expect(week.sessions[0].name == "Short tempo")
    }

    @Test func hillyRaceAddsAClimbingNoteToBuildLongRuns() throws {
        // 12-week marathon from 34.15 km a week: week 5 (build) = 34.15 x 1.1^4 = 50 km,
        // long run 40% = 20 km. 42 km, +1800 m: round10(20 x 1800/42 x 0.7) = 600 m.
        let result = plan(request(distanceKm: 42, gain: 1_800, race: LocalDate(year: 2027, month: 1, day: 3), weeklyKm: 34.15))
        #expect(result.weeks[4].phase == .build)
        let long = try #require(result.weeks[4].sessions.first { $0.type == .long })
        #expect(long.distanceKm == 20)
        #expect(long.note == "Include about 600 m of climbing.")
        let baseLong = result.weeks[0].sessions.first { $0.type == .long }
        #expect(baseLong?.note == nil)
    }

    @Test func isDeterministic() {
        #expect(plan(request()) == plan(request()))
    }

    // MARK: Other shapes

    @Test(arguments: [
        Set<Weekday>([.wednesday, .sunday]),
        [.monday, .wednesday, .friday, .sunday],
        [.monday, .tuesday, .thursday, .friday, .saturday],
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday],
    ])
    func otherDayCountsPassTheValidator(days: Set<Weekday>) {
        let request = request(days: days)
        let result = plan(request)
        #expect(PlanValidator.violations(result, request: request).isEmpty)
        #expect(result.sessions.allSatisfy { days.contains($0.date.weekday) })
    }

    @Test func twoDaysSplitLongAndQuality() {
        let week = plan(request(days: [.wednesday, .sunday])).weeks[0]
        // 17.5 km: long 55% = 9.625 -> 9.5, quality 45% = 7.875 -> 8.0.
        #expect(week.sessions.map(\.type) == [.tempo, .long])
        #expect(week.totalKm == 17.5)
    }

    @Test func buildWeeksWithFourDaysGetTwoQualitySessions() {
        let result = plan(request(days: [.monday, .wednesday, .friday, .sunday]))
        let build = result.weeks[4] // build week 2: intervals first, threshold second
        #expect(build.sessions.filter { $0.type == .intervals }.count == 1)
        #expect(build.sessions.filter { $0.type == .threshold }.count == 1)
        #expect(build.sessions.last?.type == .long)
    }

    @Test func raceExactlyFourWeeksAway() {
        // Plan start Mon 12 Oct, race Sun 8 Nov: 28 days, 4 weeks.
        let request = request(race: LocalDate(year: 2026, month: 11, day: 8))
        let result = plan(request)
        #expect(result.weeks.count == 4)
        #expect(result.weeks.last?.phase == .taper)
        #expect(PlanValidator.violations(result, request: request).isEmpty)
    }

    @Test func marathonInFourWeeksShrinksPeakThenTaper() {
        #expect(TemplatePlanGenerator.phases(kind: .marathon, weeks: 4) == [.base, .build, .peak, .taper])
    }

    @Test func zeroBaselineStartsAtTenKilometres() {
        let result = plan(request(weeklyKm: 0, pace: nil))
        #expect(result.weeks[0].targetKm == 10)
        // Shares give 2.5 / 3.5 / 4.0; the long run is at its 4 km floor, so the easy run pays.
        #expect(summary(result.weeks[0]) == ["T tempo 3.0", "Th easy 3.0", "S long 4.0"])
        #expect(result.sessions.allSatisfy { $0.estimatedMinutes == nil })
    }

    @Test func startAboveThePeakTargetStaysAtThePeak() {
        let result = plan(request(weeklyKm: 50))
        // 10K peak target is 40; weeks 1-3 sit at it, week 4 recovers to 0.8 x 40.
        #expect(Array(result.weeks.map(\.targetKm).prefix(4)) == [40, 40, 40, 32])
    }

    // MARK: Always valid

    @Test func templateOutputAlwaysPassesTheValidator() {
        let daySets: [Set<Weekday>] = [
            [.saturday, .sunday], [.monday, .tuesday], [.tuesday, .thursday, .sunday],
            [.monday, .wednesday, .friday, .saturday], [.monday, .tuesday, .wednesday, .thursday, .friday],
            [.tuesday, .wednesday, .thursday, .friday, .saturday, .sunday],
        ]
        var failures: [String] = []
        for distance in [3.0, 5, 10, 21.1, 42.2, 80] {
            for weeksOut in [4, 5, 7, 9, 12, 16, 20, 30, 52] {
                for raceWeekday in [0, 2, 5, 6] {
                    let race = PlanCalendar.planStart(today: today).adding(days: (weeksOut - 1) * 7 + raceWeekday)
                    for days in daySets {
                        for baseline in [0.0, 12, 25, 45, 90] {
                            let request = request(distanceKm: distance, gain: 900, race: race, days: days, weeklyKm: baseline)
                            guard RaceSetupValidator.issues(request.race, today: today).isEmpty else { continue }
                            let violations = PlanValidator.violations(plan(request), request: request)
                            if !violations.isEmpty {
                                failures.append("\(distance) km, \(weeksOut) w, day \(raceWeekday), \(days.count) days, \(baseline): \(violations)")
                            }
                        }
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }
}
