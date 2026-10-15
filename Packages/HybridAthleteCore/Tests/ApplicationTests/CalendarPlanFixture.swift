import Foundation
import Domain

/// The fixed plan for the calendar and session detail tests (never the
/// template generator): a 10 km race on Sun 6 Dec 2026, planStart Mon 12 Oct,
/// 8 weeks, Mon, Wed and Fri. Mon and Wed are easy runs, Fri is the long run.
enum CalendarPlanFixture {
    static func day(_ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: 2026, month: month, day: day)
    }

    static let planStart = day(10, 12)
    static let raceDay = day(12, 6)
    /// Wed 28 Oct 2026.
    static let today = day(10, 28)

    /// The spec's planned km for 12 to 30 Oct; later sessions are 6 km (Mon, Wed) and 10 km (Fri).
    static let plannedKm: [LocalDate: Double] = [
        day(10, 12): 5.0, day(10, 14): 4.5, day(10, 16): 9.0,
        day(10, 19): 5.5, day(10, 21): 5.0, day(10, 23): 10.0,
        day(10, 26): 6.0, day(10, 28): 6.5, day(10, 30): 10.0,
    ]

    static func session(on date: LocalDate) -> PlannedSession {
        let isLong = date.weekday == .friday
        let km = plannedKm[date] ?? (isLong ? 10 : 6)
        return PlannedSession(
            date: date,
            type: isLong ? .long : .easy,
            name: isLong ? "Long run" : "Easy run",
            distanceKm: km,
            // 14 Oct has no estimate.
            estimatedMinutes: date == day(10, 14) ? nil : Int(km * 6),
            effort: isLong ? "Steady, conversational" : "Easy, relaxed",
            segments: isLong
                ? [Segment(label: "Warm-up", detail: "Easy jog", distanceKm: 1.0),
                   Segment(label: "Long run", detail: "Steady pace", distanceKm: km - 2),
                   Segment(label: "Cool-down", detail: "Walk it out", distanceKm: nil)]
                : [Segment(label: "Easy run", detail: "Conversational pace", distanceKm: km)],
            // 23 Oct carries a terrain note.
            note: date == day(10, 23) ? "Rolling hills: keep the effort even on the climbs." : nil
        )
    }

    static let plan: TrainingPlan = {
        let phases: [PlanPhase] = [.base, .base, .base, .build, .build, .peak, .peak, .taper]
        let weeks = (0..<8).map { index -> PlanWeek in
            let monday = planStart.adding(days: index * 7)
            let sessions = [0, 2, 4].map { session(on: monday.adding(days: $0)) }
            return PlanWeek(index: index + 1, startDate: monday, phase: phases[index], targetKm: 22, sessions: sessions)
        }
        return TrainingPlan(
            id: "fixture", createdAt: Date(timeIntervalSince1970: 0), generatedBy: "test", planKind: .tenK,
            race: RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: raceDay, trainingDays: [.monday, .wednesday, .friday]),
            planStart: planStart, weeks: weeks
        )
    }()

    /// The spec's runs: none on 21 Oct and none today.
    static let runs: [CompletedRun] = [
        run(day(10, 12), 5.0, 1800), run(day(10, 14), 4.6, 1656), run(day(10, 16), 9.2, 3312),
        run(day(10, 19), 5.5, 1980), run(day(10, 23), 7.0, 2520), run(day(10, 26), 6.2, 2046),
    ]

    static func run(_ date: LocalDate, _ km: Double, _ seconds: Double) -> CompletedRun {
        CompletedRun(id: "run-\(date)", localDate: date, distanceKm: km, durationSeconds: seconds)
    }
}
