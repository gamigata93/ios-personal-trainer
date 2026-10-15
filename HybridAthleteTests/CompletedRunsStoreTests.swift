import Foundation
import Testing
import Domain
import Application
@testable import HybridAthlete

/// The shared runs store: one refresh at a time, staleness, locked.
@MainActor
struct CompletedRunsStoreTests {
    /// Counts reads; a read can be held open, locked or moved in time.
    private actor CountingHealth: HealthDataSource {
        private(set) var reads = 0
        private var held = false
        private var gate: CheckedContinuation<Void, Never>?
        private var error: HealthDataError?

        func hold() { held = true }
        func release() { held = false; gate?.resume(); gate = nil }
        func set(error: HealthDataError?) { self.error = error }
        var isWaiting: Bool { gate != nil }

        func authorizationRequestStatus() async -> HealthAuthorizationRequestStatus { .alreadyRequested }
        func requestAccess() async throws {}
        func readProfile() async throws -> HealthProfile { HealthProfile(ageYears: nil, biologicalSex: nil) }
        func readSamples(_ kind: HealthMetricKind, since: Date?, limit: Int?) async throws -> [HealthSample] { [] }
        func readWorkouts(routeCheckLimit: Int) async throws -> [WorkoutSummary] { [] }
        func sleepSegments(from: Date, to: Date) async throws -> [SleepSegment] { [] }
        func hrvSamples(from: Date, to: Date) async throws -> [HRVSample] { [] }
        func restingHeartRateSamples(from: Date, to: Date) async throws -> [RestingHRSample] { [] }

        func runningWorkouts(from: LocalDate, to: LocalDate) async throws -> [RunSummary] {
            reads += 1
            if held { await withCheckedContinuation { gate = $0 } }
            if let error { throw error }
            return []
        }
    }

    /// A clock the test moves; it starts on Wed 28 Oct 2026, inside the stub plan.
    private final class MovingClock: Clock, @unchecked Sendable {
        var date = Date(timeIntervalSince1970: 1_793_178_000)
        func now() -> Date { date }
    }

    private func makeStore(_ health: CountingHealth, clock: MovingClock) async -> CompletedRunsStore {
        let plans = ActivePlanStore(plans: StubPlans(hasPlan: true))
        await plans.reload()
        let cache = StubRunsCache()
        return CompletedRunsStore(
            plans: plans,
            loadCompletedRuns: LoadCompletedRuns(cache: cache),
            refreshCompletedRuns: RefreshCompletedRuns(health: health, cache: cache, clock: clock, calendar: Calendar(identifier: .gregorian)),
            clock: clock
        )
    }

    @Test func refreshIfStaleSkipsUnderFiveMinutes() async {
        let health = CountingHealth()
        let clock = MovingClock()
        let store = await makeStore(health, clock: clock)
        await store.refreshIfStale()
        #expect(await health.reads == 1)
        clock.date = clock.date.addingTimeInterval(4 * 60)
        await store.refreshIfStale()
        #expect(await health.reads == 1)
        clock.date = clock.date.addingTimeInterval(60)
        await store.refreshIfStale()
        #expect(await health.reads == 2)
    }

    @Test func twoSimultaneousRefreshesReadOnce() async {
        let health = CountingHealth()
        let store = await makeStore(health, clock: MovingClock())
        await health.hold()
        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        // Bounded, so a broken store fails the test instead of hanging it.
        for _ in 0..<100_000 where await !health.isWaiting { await Task.yield() }
        #expect(await health.isWaiting)
        #expect(store.state == .refreshing)
        await health.release()
        _ = await (first, second)
        #expect(await health.reads == 1)
        #expect(store.state == .idle)
    }

    @Test func lockedExposesTheCacheTime() async {
        let health = CountingHealth()
        await health.set(error: .locked)
        let store = await makeStore(health, clock: MovingClock())
        await store.refresh()
        // Nothing was cached, so there is no time to show.
        #expect(store.state == .locked(asOf: nil))
        #expect(await health.reads == 1)
        #expect(store.result.isLocked)
    }
}
