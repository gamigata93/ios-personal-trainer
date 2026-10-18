import Foundation
import Testing
import GRDB
import Application
import Domain
@testable import Infrastructure

@Suite("Strength, feedback and adjustments in GRDB")
struct StrengthFeedbackPersistenceTests {
    private struct FixedClock: Clock {
        func now() -> Date { Date(timeIntervalSince1970: 1_793_178_000) }
    }

    private static func day(_ month: Int, _ day: Int) -> LocalDate { LocalDate(year: 2026, month: month, day: day) }

    @Test func aPlanWithStrengthRoundTrips() async throws {
        let plan = SeedPlan.plan(createdAt: Date(timeIntervalSince1970: 0))
        #expect(!plan.strengthSessions.isEmpty)
        let repository = try GRDBPlanRepository.inMemory(seededWith: plan, clock: FixedClock())
        let loaded = await repository.loadActive()
        #expect(loaded == plan)
        #expect(loaded?.strengthSessions.first?.exercises.count == 5)
    }

    @Test func feedbackRoundTrips() async throws {
        let database = try DatabaseProvider.inMemory()
        let repository = GRDBWorkoutFeedbackRepository(database: database)
        let feedback = WorkoutFeedback(
            workoutId: "w1", workoutKind: .run, localDate: Self.day(10, 26), status: .reported,
            areas: [AreaReport(area: .other, otherName: "elbow", side: .right, kind: .ache, level: .mild)], note: "Tight.",
            recordedAt: Date(timeIntervalSince1970: 1_793_000_000)
        )
        try await repository.save(feedback)
        #expect(try await repository.feedback(workoutId: "w1") == feedback)
        #expect(try await repository.feedback(since: Self.day(10, 26)).count == 1)
        #expect(try await repository.feedback(since: Self.day(10, 27)).isEmpty)
        // Saving again replaces.
        let skipped = WorkoutFeedback(workoutId: "w1", workoutKind: .run, localDate: Self.day(10, 26), status: .noIssues, recordedAt: .distantPast)
        try await repository.save(skipped)
        #expect(try await repository.feedback(workoutId: "w1")?.status == .noIssues)
    }

    @Test func applyUndoAndStale() async throws {
        let plan = SeedPlan.plan(createdAt: Date(timeIntervalSince1970: 0))
        let database = try GRDBPlanRepository.seededDatabase(plan)
        let plans = GRDBPlanRepository(database: database, clock: FixedClock())
        let adjustments = GRDBPlanAdjustmentRepository(database: database, clock: FixedClock())
        let window = AdjustmentWindow(start: Self.day(10, 28), end: Self.day(11, 8))
        let report = AreaReport(area: .knee, side: .left, kind: .pain, level: .moderate)
        let trigger = AdjustmentTrigger(
            feedback: WorkoutFeedback(workoutId: "w", workoutKind: .run, localDate: Self.day(10, 26), status: .reported, areas: [report], recordedAt: .distantPast),
            report: report, reason: .pain
        )
        let change = AdjustmentBuilder.make(
            RuleBasedAdjustment.draft(plan: plan, window: window, trigger: trigger), plan: plan, window: window,
            triggerLine: report.line, writtenBy: "rules"
        )
        let first = try await adjustments.savePending(planId: plan.id, adjustment: change)
        #expect(try await adjustments.pending(planId: plan.id) == first)
        // A second suggestion dismisses the first.
        let second = try await adjustments.savePending(planId: plan.id, adjustment: change)
        #expect(try await adjustments.pending(planId: plan.id)?.id == second.id)

        try await adjustments.apply(id: second.id)
        let applied = try #require(await plans.loadActive())
        #expect(applied == change.applied(to: plan))
        #expect(applied.session(on: Self.day(10, 30))?.type == .easy)
        #expect(applied.strengthSession(on: Self.day(10, 28))?.focus == .mobility)
        #expect(try await adjustments.pending(planId: plan.id) == nil)
        // Applying twice fails; undo restores the plan.
        await #expect(throws: PlanAdjustmentError.notFound) { try await adjustments.apply(id: second.id) }
        try await adjustments.undo(id: second.id)
        #expect(await plans.loadActive() == plan)

        // A plan changed underneath: stale, nothing changes.
        let third = try await adjustments.savePending(planId: plan.id, adjustment: change)
        _ = try await plans.applyEdit(planId: plan.id, edit: .markMissed(sessionId: "2026-10-28"))
        _ = try await plans.applyEdit(planId: plan.id, edit: .move(sessionId: "2026-10-30", from: Self.day(10, 30), to: Self.day(10, 29)))
        let before = await plans.loadActive()
        await #expect(throws: PlanAdjustmentError.stale) { try await adjustments.apply(id: third.id) }
        #expect(await plans.loadActive() == before)
    }

    @Test func templatePrefersDaysWithoutARun() {
        // Six training days: the template runs on four of them, strength takes the free ones first.
        let request = PlanRequest(
            race: RaceSetup(
                distanceKm: 10, elevationGainM: 0, raceDate: Self.day(12, 6), trainingDays: [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday]
            ),
            fitness: FitnessSummary(weeklyKm: 12, longestRunKm: 8, avgPaceSecPerKm: 360), today: Self.day(10, 10), planKind: .tenK, source: .custom
        )
        let plan = TemplatePlanGenerator.plan(for: request)
        #expect(PlanValidator.violations(plan, request: request).isEmpty)
        let runs = Dictionary(plan.sessions.map { ($0.date, $0.type) }, uniquingKeysWith: { first, _ in first })
        for week in plan.weeks {
            let expected = StrengthRules.templateCount(week.phase, isRaceWeek: week.index == plan.weeks.count)
            #expect(week.strength.count <= expected)
            #expect(week.strength.allSatisfy { runs[$0.date] == nil || runs[$0.date] == .easy })
        }
        #expect(plan.weeks.first?.strength.count == 2)
        #expect(plan.weeks.last?.strength.isEmpty == true)
    }

    @Test func fakeRunsGiveStrengthWorkouts() async throws {
        let plan = SeedPlan.plan(createdAt: Date(timeIntervalSince1970: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let source = FakeRunsHealthDataSource(
            base: InMemoryHealthDataSource(clock: FixedClock()), activePlan: { plan }, clock: FixedClock(), calendar: calendar
        )
        let workouts = try await source.strengthWorkouts(from: Self.day(10, 12), to: Self.day(11, 30))
        #expect(workouts.map(\.id) == ["fake-strength-2026-10-14", "fake-strength-2026-10-21"])
        #expect(workouts.allSatisfy { $0.durationSeconds == 32 * 60 && $0.kind == .traditionalStrength })
    }

    @Test func refreshKeepsStrengthInTheCache() async throws {
        let plan = SeedPlan.plan(createdAt: Date(timeIntervalSince1970: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let source = FakeRunsHealthDataSource(
            base: InMemoryHealthDataSource(clock: FixedClock()), activePlan: { plan }, clock: FixedClock(), calendar: calendar
        )
        let cache = InMemoryCompletedRunsCache()
        let result = await RefreshCompletedRuns(health: source, strength: source, cache: cache, clock: FixedClock(), calendar: calendar).execute(for: plan)
        #expect(result.strength.map(\.localDate) == [Self.day(10, 14), Self.day(10, 21)])
        #expect(await cache.load()?.strength == result.strength)
        #expect(await LoadCompletedRuns(cache: cache).execute(for: plan).strength == result.strength)
    }
}
