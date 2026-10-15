import Foundation
import Testing
import Application
import Domain
@testable import Infrastructure

/// The `-fakeSleep` scenarios run through the real rules, with today Wed 21 Oct 2026.
struct FakeSleepScenarioTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 10_800) ?? .gmt
        return calendar
    }()

    private let today = LocalDate(year: 2026, month: 10, day: 21)

    private func overview(_ scenario: FakeSleepScenario) -> SleepCardState {
        let nights = SleepNightBuilder.build(FakeSleepHealthDataSource.segments(scenario, today: today, calendar: calendar), calendar: calendar).nights
        return GetSleepOverview(calendar: calendar, locale: Locale(identifier: "en_GB")).execute(nights: nights, today: today)
    }

    private func ready(_ scenario: FakeSleepScenario) throws -> SleepOverview {
        guard case .ready(let overview) = overview(scenario) else { throw ScenarioError() }
        return overview
    }

    private struct ScenarioError: Error {}

    @Test func normal() throws {
        let sleep = try ready(.normal)
        #expect(sleep.label == "Last night")
        #expect(sleep.durationText == "7h 30m")
        #expect(sleep.windowText == "23:15 \u{2013} 06:50")
        #expect(sleep.deltaText == "+7%")
        #expect(sleep.comparisonCaption == "vs your last 7 nights")
        #expect(sleep.stages.map(\.name) == ["Deep", "Core", "REM", "Awake"])
        #expect(sleep.stages.map(\.durationText) == ["1h 15m", "4h 35m", "1h 40m", "5m"])
        #expect(sleep.accessibilityLabel == "Sleep, last night. 7 hours 30 minutes asleep, from 23:15 to 06:50. 7 percent above your last 7 nights. Deep 1 hour 15 minutes, Core 4 hours 35 minutes, REM 1 hour 40 minutes, awake 5 minutes.")
    }

    @Test func short() throws {
        let sleep = try ready(.short)
        #expect(sleep.durationText == "6h 12m")
        #expect(sleep.deltaText == "\u{2212}14%")
        #expect(sleep.comparison?.trend == .down)
    }

    @Test func noStages() throws {
        let sleep = try ready(.noStages)
        #expect(!sleep.night.hasStages)
        #expect(sleep.stages.isEmpty)
        #expect(sleep.deltaText == "+7%")
    }

    @Test func noneAndStale() {
        #expect(overview(.none) == .noData)
        #expect(overview(.stale) == .noRecent(lastWakeDate: LocalDate(year: 2026, month: 10, day: 16)))
    }

    @Test func aNapAndASecondSourceDoNotChangeTheNight() throws {
        let normal = try ready(.normal)
        #expect(try ready(.nap) == normal)
        #expect(try ready(.twoSources) == normal)
    }
}
