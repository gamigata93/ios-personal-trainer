import Foundation
@testable import Domain

/// Small hand-built plans for progress tests.
enum PlanFixtures {
    static func day(_ month: Int, _ day: Int, _ year: Int = 2026) -> LocalDate {
        LocalDate(year: year, month: month, day: day)
    }

    static func session(_ date: LocalDate, _ type: SessionType = .easy, km: Double) -> PlannedSession {
        PlannedSession(
            date: date, type: type, name: "\(type.rawValue.capitalized) run", distanceKm: km,
            estimatedMinutes: Int(km * 6), effort: "Easy", segments: [], note: nil
        )
    }

    static func run(_ date: LocalDate, km: Double, id: String? = nil) -> CompletedRun {
        CompletedRun(id: id ?? "run-\(date)-\(km)", localDate: date, distanceKm: km, durationSeconds: km * 360)
    }

    /// Two weeks from Mon 12 Oct 2026, race on Sun 25 Oct.
    /// Week 1: Mon 12 easy 5, Wed 14 tempo 6, Sat 17 long 10. Week 2: Tue 20 easy 4, Thu 22 easy 4.
    static let twoWeeks: TrainingPlan = {
        let start = day(10, 12)
        let weeks = [
            PlanWeek(index: 1, startDate: start, phase: .base, targetKm: 21, sessions: [
                session(day(10, 12), km: 5), session(day(10, 14), .tempo, km: 6), session(day(10, 17), .long, km: 10),
            ]),
            PlanWeek(index: 2, startDate: start.adding(days: 7), phase: .taper, targetKm: 8, sessions: [
                session(day(10, 20), km: 4), session(day(10, 22), km: 4),
            ]),
        ]
        return TrainingPlan(
            id: "two-weeks", createdAt: Date(timeIntervalSince1970: 0), generatedBy: "test", planKind: .tenK,
            race: RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: day(10, 25), trainingDays: [.monday, .wednesday, .saturday]),
            planStart: start, weeks: weeks
        )
    }()
}
