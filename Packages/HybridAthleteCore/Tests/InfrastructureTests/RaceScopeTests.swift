import Foundation
import Testing
import Application
import Domain
@testable import Infrastructure

@Suite("Race scope with the real template")
struct RaceScopeTests {
    private struct FixedClock: Clock {
        /// Sat 10 Oct 2026, 09:00 UTC.
        func now() -> Date { Date(timeIntervalSince1970: 1_791_622_800) }
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private var today: LocalDate { LocalDate(date: FixedClock().now(), calendar: Self.utc) }

    private func setup(km: Double, weeks: Int, days: Set<Weekday>) -> RaceSetup {
        RaceSetup(
            distanceKm: km, elevationGainM: 0,
            raceDate: PlanCalendar.planStart(today: today).adding(days: 7 * weeks - 1), trainingDays: days
        )
    }

    @Test func inBetweenDistancesKeepTheirPhaseLayout() {
        // 15 km in 10 weeks: half rules, taper 2, peak 2, base 3, build 3.
        #expect(PlanKind.from(distanceKm: 15) == .halfMarathon)
        #expect(TemplatePlanGenerator.phases(kind: .halfMarathon, weeks: 10)
            == [.base, .base, .base, .build, .build, .build, .peak, .peak, .taper, .taper])
        // 30 km in 14 weeks: marathon rules, taper 3, peak 2, base round(0.45 x 9) = 4, build 5.
        #expect(PlanKind.from(distanceKm: 30) == .marathon)
        let marathon = TemplatePlanGenerator.phases(kind: .marathon, weeks: 14)
        #expect(marathon.filter { $0 == .base }.count == 4)
        #expect(marathon.filter { $0 == .build }.count == 5)
        #expect(marathon.filter { $0 == .peak }.count == 2)
        #expect(marathon.filter { $0 == .taper }.count == 3)
    }

    @Test(arguments: [(5.0, 8), (15.0, 10), (42.2, 16)])
    func inScopeDistancesCreateValidPlans(_ km: Double, _ weeks: Int) async throws {
        let plans = try GRDBPlanRepository.inMemory(seededWith: nil, clock: FixedClock())
        let create = CreatePlan(
            generator: TemplatePlanGenerator(), plans: plans, cache: InMemorySnapshotCache(), clock: FixedClock(), calendar: Self.utc,
            makeID: { "p" }
        )
        let plan = try await create.execute(setup(km: km, weeks: weeks, days: [.monday, .wednesday, .friday, .sunday]), source: .custom)
        #expect(plan.race.distanceKm == km)
        #expect(await plans.loadActive() == plan)
    }

    @Test func anOldHundredKilometrePlanKeepsWorking() async throws {
        // Built before the range existed (as -allowAnyDistance still can).
        let request = PlanRequest(
            race: setup(km: 100, weeks: 16, days: [.monday, .wednesday, .friday, .sunday]),
            fitness: FitnessSummary(weeklyKm: 40, longestRunKm: 25, avgPaceSecPerKm: 360), today: today, planKind: .marathon, source: .custom
        )
        let plan = TemplatePlanGenerator.plan(for: request).stamped(id: "old", createdAt: .distantPast)
        let repository = try GRDBPlanRepository.inMemory(seededWith: plan, clock: FixedClock())
        let loaded = try #require(await repository.loadActive())
        #expect(loaded == plan)
        #expect(HomeFormat.raceTitle(distanceKm: loaded.race.distanceKm) == "100 km race")
        #expect(LaunchRouteResolver.route(requestStatus: .alreadyRequested, hasActivePlan: await repository.hasActivePlan()) == .home)
        // Edits still apply.
        let session = try #require(loaded.sessions.first)
        let tuesday = session.date.adding(days: 1)
        _ = try await ApplyPlanEdit(plans: repository, clock: FixedClock(), calendar: Self.utc)
            .execute(.move(sessionId: session.id, from: session.date, to: tuesday), runs: [])
        #expect(await repository.loadActive()?.session(id: session.id)?.date == tuesday)
    }
}
