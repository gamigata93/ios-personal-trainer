import Foundation
import Testing
import Domain
import Application
import Infrastructure
@testable import HybridAthlete

/// The after-workout popup and suggested changes over the seed plan in an
/// in-memory database (Wed 28 Oct 2026, fake runs and strength). Fakes only.
@MainActor
struct FeedbackStoreTests {
    /// Wed 28 Oct 2026, 09:00 UTC.
    private struct Wednesday: Clock {
        func now() -> Date { Date(timeIntervalSince1970: 1_793_178_000) }
    }

    nonisolated static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private struct Setup {
        let store: FeedbackStore
        let plans: ActivePlanStore
        let runs: CompletedRunsStore
        let feedback: GRDBWorkoutFeedbackRepository
    }

    private func setup(asks: Bool = true) async throws -> Setup {
        let plan = SeedPlan.plan(createdAt: Date(timeIntervalSince1970: 0))
        let database = try GRDBPlanRepository.seededDatabase(plan)
        let repository = GRDBPlanRepository(database: database, clock: Wednesday())
        let plans = ActivePlanStore(plans: repository, clock: Wednesday(), calendar: Self.utc)
        await plans.loadIfNeeded()
        let health = FakeRunsHealthDataSource(
            base: InMemoryHealthDataSource(clock: Wednesday()), activePlan: { plan }, clock: Wednesday(), calendar: Self.utc
        )
        let cache = StubRunsCache()
        let runs = CompletedRunsStore(
            plans: plans,
            loadCompletedRuns: LoadCompletedRuns(cache: cache),
            refreshCompletedRuns: RefreshCompletedRuns(health: health, strength: health, cache: cache, clock: Wednesday(), calendar: Self.utc),
            clock: Wednesday()
        )
        await runs.refresh()
        let feedback = GRDBWorkoutFeedbackRepository(database: database)
        let adjustments = GRDBPlanAdjustmentRepository(database: database, clock: Wednesday())
        let load = LoadWorkoutFeedback(feedback: feedback)
        let store = FeedbackStore(
            plans: plans,
            runs: runs,
            pending: PendingFeedback(feedback: feedback, clock: Wednesday(), calendar: Self.utc),
            save: SaveWorkoutFeedback(feedback: feedback),
            load: load,
            suggest: SuggestPlanAdjustment(
                adjusting: FakePlanAdjuster(scenario: .fail, activePlan: { nil }), availability: AllAvailable(), adjustments: adjustments,
                loadFeedback: load, models: [], clock: Wednesday(), calendar: Self.utc
            ),
            adjustments: PlanAdjustments(adjustments: adjustments),
            clock: Wednesday(),
            asksAutomatically: asks
        )
        return Setup(store: store, plans: plans, runs: runs, feedback: feedback)
    }

    @Test func asksAboutTheNewestWorkoutFirstAndNeverTwice() async throws {
        let setup = try await setup()
        await setup.store.afterRefresh()
        // Fake runs: 26 Oct (run) only in the last 3 days; 21 Oct strength is older.
        #expect(setup.store.current?.id == "fake-2026-10-26")
        #expect(setup.store.isAwaiting("fake-2026-10-26"))
        await setup.store.submit(status: .noIssues, areas: [], note: nil)
        #expect(setup.store.current == nil)
        #expect(setup.store.suggestion == .none)
        await setup.store.afterRefresh()
        #expect(setup.store.current == nil)
        #expect(try await setup.feedback.feedback(workoutId: "fake-2026-10-26")?.status == .noIssues)
    }

    @Test func offWithoutAsking() async throws {
        let setup = try await setup(asks: false)
        await setup.store.afterRefresh()
        #expect(setup.store.current == nil)
    }

    @Test func painSuggestsAChangeThatAppliesAndUndoes() async throws {
        let setup = try await setup()
        await setup.store.afterRefresh()
        let original = setup.plans.plan
        await setup.store.submit(status: .reported, areas: [AreaReport(area: .knee, side: .left, kind: .pain, level: .severe)], note: "Sharp on the stairs")
        #expect(setup.store.showsSevereMessage)
        guard case .pending(let stored) = setup.store.suggestion else {
            Issue.record("no suggestion")
            return
        }
        #expect(stored.adjustment.writtenBy == "rules")
        #expect(stored.adjustment.window.start == LocalDate(year: 2026, month: 10, day: 28))
        await setup.store.apply()
        guard case .applied = setup.store.suggestion else {
            Issue.record("not applied")
            return
        }
        // Severe pain: no run today or tomorrow; Friday's long run is now easy; lower body strength is mobility.
        #expect(setup.plans.plan?.session(on: LocalDate(year: 2026, month: 10, day: 28)) == nil)
        #expect(setup.plans.plan?.session(on: LocalDate(year: 2026, month: 10, day: 30))?.type == .easy)
        #expect(setup.plans.plan?.strengthSession(on: LocalDate(year: 2026, month: 10, day: 28))?.focus == .mobility)
        await setup.store.undo()
        #expect(setup.plans.plan == original)
        #expect(setup.store.suggestion == .none)
    }

    @Test func keepPlanDismisses() async throws {
        let setup = try await setup()
        await setup.store.afterRefresh()
        await setup.store.submit(status: .reported, areas: [AreaReport(area: .calf, side: .both, kind: .pain, level: .mild)], note: nil)
        await setup.store.dismiss()
        #expect(setup.store.suggestion == .none)
        await setup.store.afterRefresh()
        #expect(setup.store.suggestion == .none)
    }

    @Test func editingThenSkipKeepsTheAnswer() async throws {
        let setup = try await setup()
        await setup.store.afterRefresh()
        await setup.store.submit(status: .reported, areas: [AreaReport(area: .calf, side: .both, kind: .ache, level: .mild)], note: nil)
        await setup.store.edit(
            workoutId: "fake-2026-10-26", kind: .run, localDate: LocalDate(year: 2026, month: 10, day: 26), title: "Run", detail: "5.7 km"
        )
        #expect(setup.store.editing?.areas.first?.area == .calf)
        await setup.store.skip()
        #expect(setup.store.current == nil)
        #expect(try await setup.feedback.feedback(workoutId: "fake-2026-10-26")?.status == .reported)
    }
}
