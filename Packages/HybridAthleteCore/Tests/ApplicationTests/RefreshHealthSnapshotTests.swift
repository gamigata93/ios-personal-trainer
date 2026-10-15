import Foundation
import Testing
import Application
import Domain

struct RefreshHealthSnapshotTests {
    private let health = FakeHealthDataSource()
    private let clock = FakeClock(FakeHealthDataSource.now)

    private func refresh(cache: FakeSnapshotCache) -> RefreshHealthSnapshot {
        RefreshHealthSnapshot(health: health, cache: cache, clock: clock)
    }

    private func collect(_ cache: FakeSnapshotCache) async -> [HealthRefreshUpdate] {
        var updates: [HealthRefreshUpdate] = []
        for await update in refresh(cache: cache).execute() { updates.append(update) }
        return updates
    }

    private static let cachedAt = FakeHealthDataSource.now.addingTimeInterval(-3_600)

    private static let cachedWorkouts = WorkoutsSummary(
        totalCount: 7, runCount: 3, runHeartRateAverage: 140, personalRecords: [],
        volume: RunningVolume(weeklyKm: 12, longestRunKm: 8)
    )

    @Test func everySectionReportsBetweenStartedAndFinished() async {
        await health.set(workouts: .success([FakeHealthDataSource.run(id: "5k", meters: 5_000, seconds: 1_500, heartRate: 160)]))
        let updates = await collect(FakeSnapshotCache())

        guard case .started(let start) = updates.first, case .finished = updates.last else {
            Issue.record("expected started first and finished last: \(updates)")
            return
        }
        #expect(start == FakeHealthDataSource.now)
        #expect(Set(updates.compactMap(\.section)) == Set(HealthSection.allCases))
        #expect(updates.contains(.vo2Max(.ready(
            VO2MaxSummary(latest: FakeHealthDataSource.sample(46, unit: "ml/(kg·min)"), recent: [FakeHealthDataSource.sample(46, unit: "ml/(kg·min)")]),
            asOf: FakeHealthDataSource.now, fromCache: false
        ))))
    }

    @Test func workoutsSummaryDerivesEverythingFromTheList() async {
        await health.set(workouts: .success([
            FakeHealthDataSource.run(id: "5k", meters: 5_000, seconds: 1_500, heartRate: 160, daysAgo: 3),
            FakeHealthDataSource.run(id: "old", meters: 8_000, seconds: 2_900, heartRate: 140, daysAgo: 40),
        ]))
        let updates = await collect(FakeSnapshotCache())
        let summary = updates.compactMap { if case .workouts(let state) = $0 { state.value } else { nil } }.first

        #expect(summary?.totalCount == 2)
        #expect(summary?.runCount == 1) // only the run inside 28 days
        // 1,500 s over 5 km = 300 s/km.
        #expect(summary?.volume == RunningVolume(weeklyKm: 1.25, longestRunKm: 5, avgPaceSecPerKm: 300))
        #expect(summary?.runHeartRateAverage == 150) // both runs are within 90 days
        #expect(summary?.personalRecords.map(\.workoutId) == ["5k"])
    }

    @Test func sectionsArriveInWhateverOrderTheyFinish() async throws {
        // VO2 max held until after the workouts have reported.
        await health.hold(.vo2Max)
        let stream = refresh(cache: FakeSnapshotCache()).execute()
        var order: [HealthSection] = []
        for await update in stream {
            if let section = update.section {
                order.append(section)
                if section == .workouts { await health.release(.vo2Max) }
            }
        }
        #expect(order.last == .vo2Max)
        #expect(order.firstIndex(of: .workouts).map { $0 < 3 } == true)
    }

    @Test func oneFailingSectionDoesNotBlockTheOthers() async {
        await health.set(vo2Max: .failure(.failed), workouts: .failure(.notAllowed))
        let updates = await collect(FakeSnapshotCache())
        #expect(updates.contains(.vo2Max(.failed)))
        #expect(updates.contains(.workouts(.emptyOrNotAllowed)))
        #expect(updates.contains { if case .restingHeartRate(.ready) = $0 { true } else { false } })
        #expect(updates.contains { if case .profile(.ready) = $0 { true } else { false } })
    }

    @Test func lockedSectionReturnsTheCachedValueWithItsDate() async {
        await health.set(workouts: .failure(.locked))
        let cache = FakeSnapshotCache(stored: CachedSnapshot(
            generatedAt: Self.cachedAt,
            workouts: CachedSection(value: Self.cachedWorkouts, asOf: Self.cachedAt)
        ))
        let updates = await collect(cache)
        #expect(updates.contains(.workouts(.locked(cachedValue: Self.cachedWorkouts, asOf: Self.cachedAt))))
    }

    @Test func lockedWithNoCacheHasNothingToShow() async {
        await health.set(workouts: .failure(.locked))
        let updates = await collect(FakeSnapshotCache())
        #expect(updates.contains(.workouts(.locked(cachedValue: nil, asOf: nil))))
    }

    @Test func eachOkSectionIsSavedAsItArrives() async throws {
        await health.set(vo2Max: .failure(.locked), workouts: .success([
            FakeHealthDataSource.run(id: "run", meters: 8_000, seconds: 2_900, heartRate: 145),
        ]))
        let cache = FakeSnapshotCache()
        _ = await collect(cache)

        // Profile, resting HR and workouts were ok: three saves. VO2 max was not.
        #expect(await cache.saveCount == 3)
        let stored = try #require(await cache.stored)
        #expect(stored.profile?.value == ProfileSummary(ageYears: 34, biologicalSex: .female))
        #expect(stored.restingHeartRate?.value.latest.value == 52)
        #expect(stored.workouts?.value.totalCount == 1)
        #expect(stored.vo2Max == nil)
        #expect(stored.generatedAt == FakeHealthDataSource.now)
    }

    @Test func freshSectionsReplaceCachedOnesAndKeepTheRest() async throws {
        await health.set(workouts: .failure(.locked))
        let cache = FakeSnapshotCache(stored: CachedSnapshot(
            generatedAt: Self.cachedAt,
            workouts: CachedSection(value: Self.cachedWorkouts, asOf: Self.cachedAt)
        ))
        _ = await collect(cache)
        let stored = try #require(await cache.stored)
        #expect(stored.workouts == CachedSection(value: Self.cachedWorkouts, asOf: Self.cachedAt))
        #expect(stored.vo2Max?.asOf == FakeHealthDataSource.now)
    }

    @Test func aCorruptCacheIsIgnored() async {
        await health.set(workouts: .failure(.locked))
        let cache = FakeSnapshotCache(
            stored: CachedSnapshot(generatedAt: Self.cachedAt, workouts: CachedSection(value: Self.cachedWorkouts, asOf: Self.cachedAt)),
            corrupt: true
        )
        let updates = await collect(cache)
        #expect(updates.contains(.workouts(.locked(cachedValue: nil, asOf: nil))))
        #expect(updates.contains { if case .vo2Max(.ready) = $0 { true } else { false } })
    }

    @Test func stalenessUsesTheFiveMinuteInterval() {
        let refresh = refresh(cache: FakeSnapshotCache())
        let now = FakeHealthDataSource.now
        #expect(refresh.isStale(lastRefreshStart: nil))
        #expect(!refresh.isStale(lastRefreshStart: now.addingTimeInterval(-299)))
        #expect(refresh.isStale(lastRefreshStart: now.addingTimeInterval(-300)))
    }
}
