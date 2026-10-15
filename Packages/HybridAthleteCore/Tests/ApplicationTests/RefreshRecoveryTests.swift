import Foundation
import Testing
import Application
import Domain

/// Fakes only, UTC+3, now = Wed 21 Oct 2026 10:00 local.
struct RefreshRecoveryTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 10_800) ?? .gmt
        return calendar
    }()

    static func local(_ day: LocalDate, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)) ?? .distantPast
    }

    static func day(_ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: 2026, month: month, day: day)
    }

    static var now: Date { local(day(10, 21), 10) }

    /// Two Watch samples on `wake` at 02:00 and 04:00 (the fallback window) averaging `mean`.
    static func hrvSamples(_ wake: LocalDate, mean: Double, source: String = "Apple Watch") -> [HRVSample] {
        [HRVSample(date: local(wake, 2), valueMs: mean - 2, source: source), HRVSample(date: local(wake, 4), valueMs: mean + 2, source: source)]
    }

    static func hrvNight(_ wake: LocalDate, _ mean: Double, kind: HRVNight.WindowKind = .overnightFallback) -> HRVNight {
        HRVNight(wakeDate: wake, meanMs: mean, sampleCount: 2, windowKind: kind, sourceLabel: "Apple Watch")
    }

    static func restingSample(_ date: LocalDate, _ bpm: Double) -> RestingHRSample {
        RestingHRSample(endDate: local(date, 7, 30), bpm: bpm, source: "Apple Watch")
    }

    static func restingDay(_ date: LocalDate, _ bpm: Double) -> RestingHRDay {
        RestingHRDay(date: date, bpm: bpm, sourceLabel: "Apple Watch")
    }

    private typealias T = RefreshRecoveryTests

    private func refresh(_ health: FakeHealthDataSource, _ cache: FakeRecoveryCache) -> RefreshRecovery {
        RefreshRecovery(health: health, cache: cache, clock: FakeClock(T.now), calendar: T.calendar)
    }

    @Test func theWindowStartsAtNoonFifteenDaysBack() async throws {
        let health = FakeHealthDataSource()
        _ = await refresh(health, FakeRecoveryCache()).refreshHRV(sleepNights: [])
        let window = try #require(await health.hrvWindows.first)
        // 2026-10-06 12:00 local is 09:00Z.
        #expect(window.start == (try #require(ISO8601DateFormatter().date(from: "2026-10-06T09:00:00Z"))))
        #expect(window.end == T.now)
    }

    @Test func freshHRVReplacesTheWindowOlderStaysAndSixteenAreKept() async {
        let health = FakeHealthDataSource()
        await health.set(hrv: .success(T.hrvSamples(T.day(10, 15), mean: 70) + T.hrvSamples(T.day(10, 21), mean: 58)))
        // Cached 15 Sep to 20 Oct at 50 each.
        let start = T.day(9, 15)
        let cached = (0...35).map { T.hrvNight(start.adding(days: $0), 50) }
        let cache = FakeRecoveryCache(CachedRecovery(generatedAt: T.now.addingTimeInterval(-86_400), hrv: cached, restingHr: [T.restingDay(T.day(10, 20), 50)]))

        let result = await refresh(health, cache).refreshHRV(sleepNights: [])
        // Kept: before 7 Oct (15 Sep to 6 Oct), plus fresh 15 and 21 Oct; the newest 16.
        let expected = (0...13).map { T.hrvNight(T.day(9, 23).adding(days: $0), 50) } + [T.hrvNight(T.day(10, 15), 70), T.hrvNight(T.day(10, 21), 58)]
        #expect(result.state == .ready(expected, asOf: T.now, fromCache: false))
        let stored = await cache.stored
        #expect(stored?.hrv == expected)
        // The resting heart rate half is left alone.
        #expect(stored?.restingHr == [T.restingDay(T.day(10, 20), 50)])
    }

    @Test func freshRestingHRReplacesTheWindow() async {
        let health = FakeHealthDataSource()
        await health.set(restingHR: .success([T.restingSample(T.day(10, 21), 49)]))
        let cached = [T.restingDay(T.day(10, 5), 55), T.restingDay(T.day(10, 21), 60)]
        let cache = FakeRecoveryCache(CachedRecovery(generatedAt: T.now, hrv: [], restingHr: cached))

        let result = await refresh(health, cache).refreshRestingHR()
        #expect(result.state == .ready([T.restingDay(T.day(10, 5), 55), T.restingDay(T.day(10, 21), 49)], asOf: T.now, fromCache: false))
    }

    @Test func bothMetricsSavedTogetherKeepEachOthersHalf() async {
        let health = FakeHealthDataSource()
        await health.set(hrv: .success(T.hrvSamples(T.day(10, 21), mean: 58)))
        await health.set(restingHR: .success([T.restingSample(T.day(10, 21), 49)]))
        let cache = FakeRecoveryCache()
        let use = refresh(health, cache)
        async let hrv = use.refreshHRV(sleepNights: [])
        async let resting = use.refreshRestingHR()
        _ = await (hrv, resting)
        let stored = await cache.stored
        #expect(stored?.hrv == [T.hrvNight(T.day(10, 21), 58)])
        #expect(stored?.restingHr == [T.restingDay(T.day(10, 21), 49)])
    }

    @Test func lockedReturnsTheCacheAndItsTime() async {
        let health = FakeHealthDataSource()
        await health.set(hrv: .failure(.locked))
        await health.set(restingHR: .failure(.locked))
        let cachedAt = T.now.addingTimeInterval(-3_600)
        let cache = FakeRecoveryCache(CachedRecovery(generatedAt: cachedAt, hrv: [T.hrvNight(T.day(10, 20), 60)], restingHr: []))
        let use = refresh(health, cache)
        #expect(await use.refreshHRV(sleepNights: []).state == .locked(cachedValue: [T.hrvNight(T.day(10, 20), 60)], asOf: cachedAt))
        #expect(await use.refreshRestingHR().state == .locked(cachedValue: nil, asOf: nil))
    }

    @Test func emptyWithACacheShowsTheCache() async {
        let cachedAt = T.now.addingTimeInterval(-3_600)
        let cache = FakeRecoveryCache(CachedRecovery(generatedAt: cachedAt, hrv: [T.hrvNight(T.day(10, 20), 60)], restingHr: [T.restingDay(T.day(10, 20), 50)]))
        let use = refresh(FakeHealthDataSource(), cache)
        #expect(await use.refreshHRV(sleepNights: []).state == .ready([T.hrvNight(T.day(10, 20), 60)], asOf: cachedAt, fromCache: true))
        #expect(await use.refreshRestingHR().state == .ready([T.restingDay(T.day(10, 20), 50)], asOf: cachedAt, fromCache: true))
        #expect(await cache.saveCount == 0)
    }

    @Test func emptyWithNoCacheIsEmptyOrNotAllowed() async {
        let use = refresh(FakeHealthDataSource(), FakeRecoveryCache())
        #expect(await use.refreshHRV(sleepNights: []).state == .emptyOrNotAllowed)
        #expect(await use.refreshRestingHR().state == .emptyOrNotAllowed)
    }

    @Test func otherErrorsKeepTheCache() async {
        let health = FakeHealthDataSource()
        await health.set(hrv: .failure(.failed))
        await health.set(restingHR: .failure(.unavailable))
        let stored = CachedRecovery(generatedAt: T.now, hrv: [T.hrvNight(T.day(10, 20), 60)], restingHr: [T.restingDay(T.day(10, 20), 50)])
        let cache = FakeRecoveryCache(stored)
        let use = refresh(health, cache)
        #expect(await use.refreshHRV(sleepNights: []).state == .failed)
        #expect(await use.refreshRestingHR().state == .failed)
        #expect(await cache.stored == stored)
        #expect(await cache.saveCount == 0)
    }

    @Test func theCachedSummariesLoadFirst() async {
        let cache = FakeRecoveryCache(CachedRecovery(generatedAt: T.now, hrv: [T.hrvNight(T.day(10, 20), 60)], restingHr: []))
        let loaded = await LoadCachedRecovery(cache: cache).execute()
        #expect(loaded.hrv == .ready([T.hrvNight(T.day(10, 20), 60)], asOf: T.now, fromCache: true))
        #expect(loaded.restingHr == .loading)
    }

    // MARK: Cards

    @Test func theCardsAreWorded() throws {
        let prior: [Double] = [62, 60, 64, 59, 61, 63, 62]
        let nights = prior.enumerated().map { T.hrvNight(T.day(10, 14 + $0.offset), $0.element, kind: .sleep) } + [T.hrvNight(T.day(10, 21), 58, kind: .sleep)]
        let days = [50.0, 51, 50, 52, 50, 51, 50].enumerated().map { T.restingDay(T.day(10, 14 + $0.offset), $0.element) } + [T.restingDay(T.day(10, 21), 49)]
        let state = GetRecoveryOverview().execute(hrv: nights, restingHr: days, today: T.day(10, 21))

        guard case .ready(let hrv) = state.hrv, case .ready(let resting) = state.restingHr else {
            Issue.record("Expected both cards ready")
            return
        }
        #expect(hrv.valueText == "58")
        #expect(hrv.unit == "ms")
        #expect(hrv.label == "Last night")
        #expect(hrv.deltaText == "\u{2212}6%")
        #expect(hrv.caption == "vs last 7 nights")
        #expect(hrv.comparison?.outcome == .worse)
        #expect(hrv.accessibilityLabel == "Heart rate variability, last night. 58 milliseconds, 6 percent below your last 7 nights.")
        #expect(resting.valueText == "49")
        #expect(resting.unit == "bpm")
        #expect(resting.label == "Today")
        #expect(resting.deltaText == "About the same")
        #expect(resting.caption == "vs last 7 days")
        #expect(resting.accessibilityLabel == "Resting heart rate, today. 49 beats per minute, about the same as your last 7 days.")
    }

    @Test func theSectionLines() {
        let home = GetHomeOverview(
            clock: FakeClock(T.now), calendar: T.calendar,
            sleepOverview: GetSleepOverview(calendar: T.calendar, locale: Locale(identifier: "en_GB")),
            recoveryOverview: GetRecoveryOverview()
        )
        func section(_ states: RecoveryStates) -> RecoveryOverview {
            home.execute(plan: FakePlanRepository.samplePlan, runs: .none, recovery: states).recovery
        }
        let earlier = T.now.addingTimeInterval(-600)
        let locked = section(RecoveryStates(
            sleep: .ready([], asOf: T.now, fromCache: false),
            hrv: .locked(cachedValue: [T.hrvNight(T.day(10, 21), 58)], asOf: earlier),
            restingHr: .failed
        ))
        #expect(locked.lockedNotice == "Your phone is locked. Showing recovery from 10 min ago.")
        #expect(locked.updatedLabel == "Updated just now")
        #expect(locked.accessNotice == nil)
        #expect(locked.restingHr.body == .failed)

        let lockedEmpty = section(RecoveryStates(restingHr: .locked(cachedValue: nil, asOf: nil)))
        #expect(lockedEmpty.lockedNotice == "Your phone is locked. Recovery updates after you unlock it.")
        #expect(lockedEmpty.restingHr.body == .lockedNoCache)
        #expect(lockedEmpty.hrv.body == .loading)

        let empty = section(RecoveryStates(hrv: .emptyOrNotAllowed))
        #expect(empty.accessNotice == "If you declined access, allow it in Settings, Health, Data Access & Devices.")
        #expect(empty.hrv.body == .noData)
        #expect(empty.lockedNotice == nil)

        let stale = section(RecoveryStates(restingHr: .ready([T.restingDay(T.day(10, 17), 50)], asOf: T.now, fromCache: false)))
        #expect(stale.restingHr.body == .noRecent(last: "Last: Sat 17 Oct."))
    }
}

/// Recovery summaries in memory, counting saves.
actor FakeRecoveryCache: RecoveryCache {
    private(set) var stored: CachedRecovery?
    private(set) var saveCount = 0

    init(_ stored: CachedRecovery? = nil) {
        self.stored = stored
    }

    func load() async -> CachedRecovery? { stored }

    func save(_ recovery: CachedRecovery) async throws {
        saveCount += 1
        stored = recovery
    }
}
