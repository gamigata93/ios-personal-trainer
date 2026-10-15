import Foundation
import Domain

/// The fixed plan for the plan-edit tests (never the template generator): a 10 km
/// race on Sun 6 Dec 2026, planStart Mon 12 Oct, sessions on Mon, Wed and Fri
/// through Fri 4 Dec. Session ids are the original dates. Mondays are tempo runs
/// (2 Nov is a threshold run), Wednesdays easy runs, Fridays long runs.
enum EditPlanFixture {
    static func day(_ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: 2026, month: month, day: day)
    }

    static let planStart = day(10, 12)
    static let raceDay = day(12, 6)
    /// Wed 28 Oct 2026.
    static let today = day(10, 28)

    /// The spec's km; later sessions are 6 km (Mon, Wed) and 10 km (Fri).
    static let plannedKm: [LocalDate: Double] = [
        day(10, 12): 5.0, day(10, 14): 4.5, day(10, 16): 9.0,
        day(10, 19): 5.5, day(10, 21): 5.0, day(10, 23): 10.0,
        day(10, 26): 6.0, day(10, 28): 6.5, day(10, 30): 10.0,
        day(11, 2): 5.0, day(11, 4): 6.0, day(11, 6): 7.0,
    ]

    static func session(on date: LocalDate) -> PlannedSession {
        let type: SessionType
        let name: String
        switch date.weekday {
        case .monday where date == day(11, 2): (type, name) = (.threshold, "Threshold run")
        case .monday: (type, name) = (.tempo, "Tempo run")
        case .wednesday: (type, name) = (.easy, "Easy run")
        default: (type, name) = (.long, "Long run")
        }
        let km = plannedKm[date] ?? (type == .long ? 10 : 6)
        return PlannedSession(
            date: date, type: type, name: name, distanceKm: km, estimatedMinutes: Int(km * 6),
            effort: type == .easy ? "Easy" : "Hard",
            segments: [Segment(label: "Warm-up", detail: "Easy jog", distanceKm: 1), Segment(label: "Main", detail: name, distanceKm: km - 1)],
            note: date == day(10, 23) ? "Rolling hills." : nil
        )
    }

    /// Mon, Wed and Fri from 12 Oct through Fri 4 Dec, plus `extra` days.
    static func plan(extra: [LocalDate] = []) -> TrainingPlan {
        let phases: [PlanPhase] = [.base, .base, .base, .build, .build, .peak, .peak, .taper]
        let weeks = (0..<8).map { index -> PlanWeek in
            let monday = planStart.adding(days: index * 7)
            let week = (0..<7).map { monday.adding(days: $0) }
            let days = week.filter { [Weekday.monday, .wednesday, .friday].contains($0.weekday) || extra.contains($0) }
            return PlanWeek(index: index + 1, startDate: monday, phase: phases[index], targetKm: 22, sessions: days.map(session(on:)))
        }
        return TrainingPlan(
            id: "fixture", createdAt: Date(timeIntervalSince1970: 1_790_000_000), generatedBy: "test", planKind: .tenK,
            race: RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: raceDay, trainingDays: [.monday, .wednesday, .friday]),
            planStart: planStart, weeks: weeks
        )
    }

    static let base = plan()

    /// None on 21 Oct, none today.
    static let runs: [CompletedRun] = [
        run(day(10, 12), 5.0), run(day(10, 14), 4.6), run(day(10, 16), 9.2),
        run(day(10, 19), 5.5), run(day(10, 23), 7.0), run(day(10, 26), 6.2),
    ]

    static func run(_ date: LocalDate, _ km: Double) -> CompletedRun {
        CompletedRun(id: "run-\(date)", localDate: date, distanceKm: km, durationSeconds: km * 360)
    }

    /// The session id for a day: its original date.
    static func id(_ month: Int, _ d: Int) -> String {
        day(month, d).description
    }
}
