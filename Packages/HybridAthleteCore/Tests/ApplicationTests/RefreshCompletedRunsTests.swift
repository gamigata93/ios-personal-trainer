import Foundation
import Testing
import Application
import Domain

struct RefreshCompletedRunsTests {
    private let sofia: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Sofia") ?? .gmt
        return calendar
    }()

    /// Wed 28 Oct 2026, 09:00 UTC (12:00 in Sofia).
    private let now = Date(timeIntervalSince1970: 1_793_178_000)
    /// Plan start Mon 12 Oct 2026, race Sun 6 Dec 2026, id "sample".
    private let plan = FakePlanRepository.samplePlan

    private func refresh(_ health: FakeHealthDataSource, _ cache: FakeRunsCache, at date: Date? = nil) -> RefreshCompletedRuns {
        RefreshCompletedRuns(health: health, cache: cache, clock: FakeClock(date ?? now), calendar: sofia)
    }

    private func date(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    @Test func mapsRunsToLocalDaysAndSavesThem() async throws {
        let health = FakeHealthDataSource()
        await health.set(runs: .success([
            RunSummary(id: "late", startDate: try date("2026-10-12T20:30:00Z"), distanceMeters: 5_000, durationSeconds: 1_700),
            RunSummary(id: "after-midnight", startDate: try date("2026-10-12T22:00:00Z"), distanceMeters: 4_200, durationSeconds: 1_500),
        ]))
        let cache = FakeRunsCache()
        let result = await refresh(health, cache).execute(for: plan)

        #expect(result.source == .fresh)
        #expect(result.asOf == now)
        #expect(result.runs == [
            CompletedRun(id: "late", localDate: LocalDate(year: 2026, month: 10, day: 12), distanceKm: 5, durationSeconds: 1_700),
            CompletedRun(id: "after-midnight", localDate: LocalDate(year: 2026, month: 10, day: 13), distanceKm: 4.2, durationSeconds: 1_500),
        ])
        #expect(await health.runRanges == [LocalDate(year: 2026, month: 10, day: 12)...LocalDate(year: 2026, month: 10, day: 28)])
        #expect(await cache.stored == CachedRuns(generatedAt: now, planId: "sample", runs: result.runs))
    }

    @Test func readsNoFurtherThanRaceDay() async throws {
        let health = FakeHealthDataSource()
        _ = await refresh(health, FakeRunsCache(), at: try date("2026-12-20T09:00:00Z")).execute(for: plan)
        #expect(await health.runRanges.last?.upperBound == LocalDate(year: 2026, month: 12, day: 6))
    }

    @Test func beforeThePlanStartsNothingIsRead() async throws {
        let health = FakeHealthDataSource()
        let result = await refresh(health, FakeRunsCache(), at: try date("2026-10-10T09:00:00Z")).execute(for: plan)
        #expect(result.runs.isEmpty)
        #expect(await health.runRanges.isEmpty)
    }

    @Test func lockedReturnsTheCacheAndItsTime() async {
        let health = FakeHealthDataSource()
        await health.set(runs: .failure(.locked))
        let cachedAt = now.addingTimeInterval(-3_600)
        let stored = CachedRuns(generatedAt: cachedAt, planId: "sample", runs: [PlanRunFixtures.run])
        let cache = FakeRunsCache(stored)

        let result = await refresh(health, cache).execute(for: plan)
        #expect(result.source == .locked)
        #expect(result.runs == [PlanRunFixtures.run])
        #expect(result.asOf == cachedAt)
        #expect(await cache.saveCount == 0)
    }

    @Test func otherErrorsKeepTheCache() async {
        let health = FakeHealthDataSource()
        await health.set(runs: .failure(.failed))
        let stored = CachedRuns(generatedAt: now, planId: "sample", runs: [PlanRunFixtures.run])
        let cache = FakeRunsCache(stored)

        let result = await refresh(health, cache).execute(for: plan)
        #expect(result.source == .cache)
        #expect(result.runs == [PlanRunFixtures.run])
        #expect(await cache.stored == stored)
        #expect(await cache.saveCount == 0)
    }

    @Test func aCacheForAnotherPlanIsIgnored() async {
        let health = FakeHealthDataSource()
        await health.set(runs: .failure(.locked))
        let cache = FakeRunsCache(CachedRuns(generatedAt: now, planId: "old-plan", runs: [PlanRunFixtures.run]))

        let locked = await refresh(health, cache).execute(for: plan)
        #expect(locked.runs.isEmpty)
        #expect(locked.asOf == nil)
        #expect(await LoadCompletedRuns(cache: cache).execute(for: plan) == .none)
    }

    @Test func loadingTheCacheShowsItsRuns() async {
        let cache = FakeRunsCache(CachedRuns(generatedAt: now, planId: "sample", runs: [PlanRunFixtures.run]))
        let result = await LoadCompletedRuns(cache: cache).execute(for: plan)
        #expect(result == CompletedRunsResult(runs: [PlanRunFixtures.run], asOf: now, source: .cache))
    }

    @Test func refreshesAgainAfterFiveMinutes() {
        let use = refresh(FakeHealthDataSource(), FakeRunsCache())
        #expect(use.isStale(lastRefreshStart: nil))
        #expect(!use.isStale(lastRefreshStart: now.addingTimeInterval(-299)))
        #expect(use.isStale(lastRefreshStart: now.addingTimeInterval(-300)))
    }
}

enum PlanRunFixtures {
    static let run = CompletedRun(id: "cached", localDate: LocalDate(year: 2026, month: 10, day: 14), distanceKm: 6, durationSeconds: 2_100)
}

/// Completed runs in memory, counting saves.
actor FakeRunsCache: CompletedRunsCache {
    private(set) var stored: CachedRuns?
    private(set) var saveCount = 0

    init(_ stored: CachedRuns? = nil) {
        self.stored = stored
    }

    func load() async -> CachedRuns? { stored }

    func save(_ runs: CachedRuns) async throws {
        saveCount += 1
        stored = runs
    }
}
