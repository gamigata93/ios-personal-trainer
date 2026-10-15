import Foundation
import Testing
import Application
import Domain
@testable import Infrastructure

/// The `-fakeRecovery` scenarios run through the real rules with `-fakeSleep
/// normal` nights, today Wed 21 Oct 2026.
struct FakeRecoveryScenarioTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 10_800) ?? .gmt
        return calendar
    }()

    private let today = LocalDate(year: 2026, month: 10, day: 21)

    private func cards(_ scenario: FakeRecoveryScenario, sleep: FakeSleepScenario = .normal) -> (RecoveryCardsState, [HRVNight]) {
        let nights = SleepNightBuilder.build(FakeSleepHealthDataSource.segments(sleep, today: today, calendar: calendar), calendar: calendar).nights
        let hrv = HRVNightBuilder.build(
            samples: FakeRecoveryHealthDataSource.hrv(scenario, today: today, calendar: calendar),
            sleepNights: nights, calendar: calendar, today: today
        ).nights
        let resting = RestingHRDayBuilder.build(FakeRecoveryHealthDataSource.restingHR(scenario, today: today, calendar: calendar), calendar: calendar).days
        return (GetRecoveryOverview().execute(hrv: hrv, restingHr: resting, today: today), hrv)
    }

    private func texts(_ state: RecoveryMetricState) -> [String?] {
        guard case .ready(let overview) = state else { return [] }
        return [overview.valueText, overview.deltaText]
    }

    @Test func mock() {
        let (state, nights) = cards(.mock)
        #expect(texts(state.hrv) == ["58", "\u{2212}6%"])
        #expect(texts(state.restingHr) == ["49", "About the same"])
        #expect(nights.last?.windowKind == .sleep)
        #expect(nights.count == 15)
    }

    @Test func goodAndStrained() {
        #expect(texts(cards(.good).0.hrv) == ["66", "+7%"])
        #expect(texts(cards(.good).0.restingHr) == ["48", "\u{2212}3 bpm"])
        #expect(texts(cards(.strained).0.hrv) == ["45", "\u{2212}27%"])
        #expect(texts(cards(.strained).0.restingHr) == ["54", "+3 bpm"])
    }

    @Test func noHrvStaleAndFewSamples() {
        #expect(cards(.noHrv).0.hrv == .noData)
        #expect(texts(cards(.noHrv).0.restingHr) == ["49", "About the same"])
        #expect(cards(.stale).0.hrv == .noRecent(lastDate: LocalDate(year: 2026, month: 10, day: 16)))
        #expect(cards(.stale).0.restingHr == .noRecent(lastDate: LocalDate(year: 2026, month: 10, day: 16)))
        // Today's single sample gives no night, so yesterday's is shown.
        guard case .ready(let few) = cards(.fewSamples).0.hrv else {
            Issue.record("Expected yesterday's night")
            return
        }
        #expect(few.label == "Yesterday")
    }

    @Test func fallbackWithoutSleep() {
        let (state, nights) = cards(.fallback, sleep: .none)
        #expect(texts(state.hrv) == ["58", "\u{2212}6%"])
        #expect(nights.last?.windowKind == .overnightFallback)
    }

    @Test func lockedSeedsTheMockCache() throws {
        let clock = ShiftedClock(base: SystemClockStub(), today: today, calendar: calendar)
        let cached = try #require(FakeRecoveryHealthDataSource.seededCache(.locked, clock: clock, calendar: calendar))
        #expect(cached.hrv.last.map { RecoveryFormat.hrvValueText($0.meanMs) } == "58")
        #expect(cached.restingHr.last?.bpm == 49)
        #expect(FakeRecoveryHealthDataSource.seededCache(.mock, clock: clock, calendar: calendar) == nil)
    }
}

/// 10:00 UTC+3 on some day; ShiftedClock moves it to `today`.
private struct SystemClockStub: Clock {
    func now() -> Date { Date(timeIntervalSince1970: 1_792_566_000) }
}
