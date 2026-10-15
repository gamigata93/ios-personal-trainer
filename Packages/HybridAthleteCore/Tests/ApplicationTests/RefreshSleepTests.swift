import Foundation
import Testing
import Application
import Domain

struct RefreshSleepTests {
    /// UTC+3, no DST.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 10_800) ?? .gmt
        return calendar
    }()

    private func local(_ day: LocalDate, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)) ?? .distantPast
    }

    private func day(_ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: 2026, month: month, day: day)
    }

    /// 2026-10-21 10:00 local.
    private var now: Date { local(day(10, 21), 10) }

    /// One unspecified block ending 06:50 on `wake`.
    private func segments(wake: LocalDate, minutes: Int) -> [SleepSegment] {
        let end = local(wake, 6, 50)
        return [SleepSegment(start: end.addingTimeInterval(-Double(minutes * 60)), end: end, stage: .asleepUnspecified, source: "Apple Watch")]
    }

    private func night(_ wake: LocalDate, _ minutes: Int) -> SleepNight {
        let end = local(wake, 6, 50)
        return SleepNight(
            wakeDate: wake, sleepStart: end.addingTimeInterval(-Double(minutes * 60)), wakeTime: end, asleepMinutes: minutes,
            deepMinutes: 0, coreMinutes: 0, remMinutes: 0, unspecifiedMinutes: minutes, awakeMinutes: 0,
            timeInBedMinutes: minutes, hasStages: false, sourceLabel: "Apple Watch"
        )
    }

    private func refresh(_ health: FakeHealthDataSource, _ cache: FakeSleepCache) -> RefreshSleep {
        RefreshSleep(health: health, cache: cache, clock: FakeClock(now), calendar: calendar)
    }

    @Test func theWindowStartsAtNoonFifteenDaysBack() async throws {
        let health = FakeHealthDataSource()
        _ = await refresh(health, FakeSleepCache()).execute()
        let window = try #require(await health.sleepWindows.first)
        // 2026-10-06 12:00 local is 09:00Z.
        #expect(window.start == (try #require(ISO8601DateFormatter().date(from: "2026-10-06T09:00:00Z"))))
        #expect(window.end == now)
    }

    @Test func freshNightsReplaceTheWindowAndOlderNightsStay() async {
        let health = FakeHealthDataSource()
        await health.set(sleep: .success(segments(wake: day(10, 15), minutes: 400) + segments(wake: day(10, 21), minutes: 450)))
        // Cached 2 to 20 Oct at 300 each.
        let cached = (2...20).map { night(day(10, $0), 300) }
        let cache = FakeSleepCache(CachedSleep(generatedAt: now.addingTimeInterval(-86_400), nights: cached))

        let result = await refresh(health, cache).execute()
        let expected = (2...6).map { night(day(10, $0), 300) } + [night(day(10, 15), 400), night(day(10, 21), 450)]
        #expect(result.state == .ready(expected, asOf: now, fromCache: false))
        #expect(result.isNewNight)
        #expect(await cache.stored == CachedSleep(generatedAt: now, nights: expected))
    }

    @Test func onlyTheNewestSixteenNightsAreKept() async {
        let health = FakeHealthDataSource()
        await health.set(sleep: .success(segments(wake: day(10, 21), minutes: 450)))
        let old = (1...20).map { night(day(9, $0), 300) }
        let cache = FakeSleepCache(CachedSleep(generatedAt: now, nights: old))

        let result = await refresh(health, cache).execute()
        let nights = result.state.value ?? []
        #expect(nights.count == 16)
        #expect(nights.first?.wakeDate == day(9, 6))
        #expect(nights.last?.wakeDate == day(10, 21))
    }

    @Test func isNewNightComparesWithTheCache() async {
        let health = FakeHealthDataSource()
        await health.set(sleep: .success(segments(wake: day(10, 21), minutes: 450)))
        #expect(await refresh(health, FakeSleepCache()).execute().isNewNight)

        let same = FakeSleepCache(CachedSleep(generatedAt: now, nights: [night(day(10, 21), 450)]))
        #expect(await !refresh(health, same).execute().isNewNight)

        let older = FakeSleepCache(CachedSleep(generatedAt: now, nights: [night(day(10, 20), 450)]))
        #expect(await refresh(health, older).execute().isNewNight)
    }

    @Test func lockedReturnsTheCacheAndItsTime() async {
        let health = FakeHealthDataSource()
        await health.set(sleep: .failure(.locked))
        let cachedAt = now.addingTimeInterval(-3_600)
        let cache = FakeSleepCache(CachedSleep(generatedAt: cachedAt, nights: [night(day(10, 20), 420)]))
        let result = await refresh(health, cache).execute()
        #expect(result.state == .locked(cachedValue: [night(day(10, 20), 420)], asOf: cachedAt))
        #expect(!result.isNewNight)
    }

    @Test func emptyWithACacheShowsTheCache() async {
        let health = FakeHealthDataSource()
        let cachedAt = now.addingTimeInterval(-3_600)
        let cache = FakeSleepCache(CachedSleep(generatedAt: cachedAt, nights: [night(day(10, 20), 420)]))
        let result = await refresh(health, cache).execute()
        #expect(result.state == .ready([night(day(10, 20), 420)], asOf: cachedAt, fromCache: true))
        #expect(await cache.saveCount == 0)
    }

    @Test func emptyWithNoCacheIsEmptyOrNotAllowed() async {
        let result = await refresh(FakeHealthDataSource(), FakeSleepCache()).execute()
        #expect(result.state == .emptyOrNotAllowed)
    }

    @Test func otherErrorsKeepTheCache() async {
        let health = FakeHealthDataSource()
        await health.set(sleep: .failure(.failed))
        let stored = CachedSleep(generatedAt: now, nights: [night(day(10, 20), 420)])
        let cache = FakeSleepCache(stored)
        let result = await refresh(health, cache).execute()
        #expect(result.state == .failed)
        #expect(await cache.stored == stored)
        #expect(await cache.saveCount == 0)
    }

    @Test func theCachedNightsLoadFirst() async {
        let cache = FakeSleepCache(CachedSleep(generatedAt: now, nights: [night(day(10, 20), 420)]))
        #expect(await LoadCachedSleep(cache: cache).execute() == .ready([night(day(10, 20), 420)], asOf: now, fromCache: true))
        #expect(await LoadCachedSleep(cache: FakeSleepCache()).execute() == .loading)
    }

    // MARK: Card

    @Test func theCardForEachState() {
        let overview = GetSleepOverview(calendar: calendar, locale: Locale(identifier: "en_GB"))
        let home = GetHomeOverview(clock: FakeClock(now), calendar: calendar, sleepOverview: overview, recoveryOverview: GetRecoveryOverview())
        func section(_ state: SectionState<[SleepNight]>) -> RecoveryOverview {
            home.execute(plan: FakePlanRepository.samplePlan, runs: .none, recovery: RecoveryStates(sleep: state)).recovery
        }
        func card(_ state: SectionState<[SleepNight]>) -> SleepCard {
            section(state).sleep
        }
        #expect(card(.loading).body == .loading)
        #expect(card(.failed).body == .failed)
        #expect(card(.emptyOrNotAllowed).body == .emptyOrNotAllowed)
        #expect(card(.locked(cachedValue: nil, asOf: nil)).body == .lockedNoCache)
        #expect(card(.ready([], asOf: now, fromCache: false)).body == .noData)
        #expect(card(.ready([night(day(10, 17), 420)], asOf: now, fromCache: false)).body == .noRecent(lastRecorded: "Last recorded: Sat 17 Oct."))

        let lockedSection = section(.locked(cachedValue: [night(day(10, 21), 420)], asOf: now.addingTimeInterval(-600)))
        #expect(lockedSection.lockedNotice == "Your phone is locked. Showing recovery from 10 min ago.")
        #expect(lockedSection.updatedLabel == "Updated 10 min ago")
        let locked = lockedSection.sleep
        guard case .overview(let shown) = locked.body else {
            Issue.record("Expected the cached night")
            return
        }
        #expect(shown.label == "Last night")
        #expect(shown.windowText == "23:50 \u{2013} 06:50")
        #expect(shown.stages.isEmpty)
        #expect(section(.ready([night(day(10, 21), 420)], asOf: now, fromCache: false)).lockedNotice == nil)
    }
}

/// Nightly summaries in memory, counting saves.
actor FakeSleepCache: SleepCache {
    private(set) var stored: CachedSleep?
    private(set) var saveCount = 0

    init(_ stored: CachedSleep? = nil) {
        self.stored = stored
    }

    func load() async -> CachedSleep? { stored }

    func save(_ sleep: CachedSleep) async throws {
        saveCount += 1
        stored = sleep
    }
}
