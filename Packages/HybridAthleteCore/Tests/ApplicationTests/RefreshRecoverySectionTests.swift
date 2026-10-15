import Foundation
import Testing
import Application
import Domain

/// The orchestration with a gated fake: what finishes when, and what HRV uses.
struct RefreshRecoverySectionTests {
    private typealias T = RefreshRecoveryTests

    /// A night waking 21 Oct at 06:50 after 450 minutes, as segments.
    private var nightSegments: [SleepSegment] {
        let end = T.local(T.day(10, 21), 6, 50)
        return [SleepSegment(start: end.addingTimeInterval(-450 * 60), end: end, stage: .core, source: "Apple Watch")]
    }

    /// HRV samples inside that night (23:20 and 06:40): outside 00:00 to 08:00 for the 23:20 one.
    private var nightHRV: [HRVSample] {
        [
            HRVSample(date: T.local(T.day(10, 20), 23, 20), valueMs: 50, source: "Apple Watch"),
            HRVSample(date: T.local(T.day(10, 21), 6, 40), valueMs: 60, source: "Apple Watch"),
        ]
    }

    private func section(
        _ health: FakeHealthDataSource,
        sleepCache: FakeSleepCache = FakeSleepCache(),
        recoveryCache: FakeRecoveryCache = FakeRecoveryCache()
    ) -> RefreshRecoverySection {
        let clock = FakeClock(T.now)
        return RefreshRecoverySection(
            refreshSleep: RefreshSleep(health: health, cache: sleepCache, clock: clock, calendar: T.calendar),
            loadCachedSleep: LoadCachedSleep(cache: sleepCache),
            refreshRecovery: RefreshRecovery(health: health, cache: recoveryCache, clock: clock, calendar: T.calendar)
        )
    }

    @Test func updatesArriveAsEachFinishesAndHRVWaitsForSleep() async throws {
        let health = FakeHealthDataSource()
        await health.set(sleep: .success(nightSegments))
        await health.set(hrv: .success(nightHRV))
        await health.set(restingHR: .success([T.restingSample(T.day(10, 21), 49)]))
        await health.holdRead("sleep")

        var updates = section(health).execute().makeAsyncIterator()
        // Sleep is held, so resting heart rate finishes first and HRV has not started.
        guard case .restingHr(let resting) = await updates.next() else {
            Issue.record("Expected resting heart rate first")
            return
        }
        #expect(resting.state.value == [T.restingDay(T.day(10, 21), 49)])
        #expect(await !health.events.contains("hrv.start"))

        await health.releaseRead("sleep")
        guard case .sleep(let sleep) = await updates.next() else {
            Issue.record("Expected sleep second")
            return
        }
        #expect(sleep.state.value?.map(\.wakeDate) == [T.day(10, 21)])
        guard case .hrv(let hrv) = await updates.next() else {
            Issue.record("Expected HRV last")
            return
        }
        // The fresh sleep window includes 23:20, so both samples count.
        let night = try #require(hrv.state.value?.first)
        #expect(night.windowKind == .sleep)
        #expect(night.meanMs == 55)
        #expect(await updates.next() == nil)

        let events = await health.events
        let sleepEnd = try #require(events.firstIndex(of: "sleep.end"))
        let hrvStart = try #require(events.firstIndex(of: "hrv.start"))
        #expect(sleepEnd < hrvStart)
    }

    @Test func lockedSleepGivesHRVTheCachedNights() async throws {
        let health = FakeHealthDataSource()
        await health.set(sleep: .failure(.locked))
        await health.set(hrv: .success(nightHRV))
        let end = T.local(T.day(10, 21), 6, 50)
        let cachedNight = SleepNight(
            wakeDate: T.day(10, 21), sleepStart: end.addingTimeInterval(-450 * 60), wakeTime: end, asleepMinutes: 450,
            deepMinutes: 0, coreMinutes: 450, remMinutes: 0, unspecifiedMinutes: 0, awakeMinutes: 0,
            timeInBedMinutes: 450, hasStages: true, sourceLabel: "Apple Watch"
        )
        let sleepCache = FakeSleepCache(CachedSleep(generatedAt: T.now, nights: [cachedNight]))

        var hrvState: SectionState<[HRVNight]>?
        for await update in section(health, sleepCache: sleepCache).execute() {
            if case .hrv(let result) = update { hrvState = result.state }
        }
        let night = try #require(hrvState?.value?.first)
        #expect(night.windowKind == .sleep)
        #expect(night.sampleCount == 2)
    }

    @Test func oneFailingMetricNeverBlocksTheOthers() async {
        let health = FakeHealthDataSource()
        await health.set(sleep: .failure(.failed))
        await health.set(hrv: .success(nightHRV))
        await health.set(restingHR: .failure(.failed))

        var seen: [String: Bool] = [:]
        for await update in section(health).execute() {
            switch update {
            case .sleep(let result): seen["sleep"] = result.state == .failed
            case .restingHr(let result): seen["restingHr"] = result.state == .failed
            // No sleep nights and nothing cached: the fallback keeps only 06:40, one sample, so no night.
            case .hrv(let result): seen["hrv"] = result.state == .ready([], asOf: T.now, fromCache: false)
            }
        }
        #expect(seen == ["sleep": true, "restingHr": true, "hrv": true])
    }
}
