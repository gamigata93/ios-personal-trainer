#if DEBUG
import Foundation
import Domain

/// The fixed plan behind the `-seedPlan` launch argument, so UI tests and
/// previews can open Home without onboarding. DEBUG builds only.
public enum SeedPlan {
    public static let id = "seed-plan"

    /// A 10 km race on Sun 6 Dec 2026, Mon/Wed/Fri, built on Sat 10 Oct 2026.
    public static let request = PlanRequest(
        race: RaceSetup(
            distanceKm: 10,
            elevationGainM: 0,
            raceDate: LocalDate(year: 2026, month: 12, day: 6),
            trainingDays: [.monday, .wednesday, .friday]
        ),
        fitness: FitnessSummary(weeklyKm: 18.44, longestRunKm: 17.0, avgPaceSecPerKm: 337),
        today: LocalDate(year: 2026, month: 10, day: 10),
        planKind: .tenK,
        source: .custom
    )

    public static func plan(createdAt: Date) -> TrainingPlan {
        TemplatePlanGenerator.plan(for: request).stamped(id: id, createdAt: createdAt)
    }
}
#endif
