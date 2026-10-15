import Foundation
import Testing
@testable import Domain

struct RecoverySelectionTests {
    private typealias F = SleepFixtures

    private let night = HRVNight(wakeDate: SleepFixtures.day(10, 21), meanMs: 58, sampleCount: 4, windowKind: .sleep, sourceLabel: "Apple Watch")
    private let day = RestingHRDay(date: SleepFixtures.day(10, 21), bpm: 49, sourceLabel: "Apple Watch")

    private func hrv(today: LocalDate, _ nights: [HRVNight]? = nil) -> RecentSelection<HRVNight> {
        RecentSelection.select(nights ?? [night], date: \.wakeDate, today: today, maxAgeDays: RecoveryRules.maxAgeDays, label: RecoveryLabel.night)
    }

    private func resting(today: LocalDate, _ days: [RestingHRDay]? = nil) -> RecentSelection<RestingHRDay> {
        RecentSelection.select(days ?? [day], date: \.date, today: today, maxAgeDays: RecoveryRules.maxAgeDays, label: RecoveryLabel.day)
    }

    @Test func labelsByAge() {
        #expect(resting(today: F.day(10, 21)) == .shown(day, label: "Today"))
        #expect(hrv(today: F.day(10, 21)) == .shown(night, label: "Last night"))
        #expect(resting(today: F.day(10, 22)) == .shown(day, label: "Yesterday"))
        #expect(hrv(today: F.day(10, 22)) == .shown(night, label: "Yesterday"))
        #expect(resting(today: F.day(10, 23)) == .shown(day, label: "Wed 21 Oct"))
        #expect(hrv(today: F.day(10, 23)) == .shown(night, label: "Wed 21 Oct"))
    }

    @Test func olderThanTwoDaysIsNoRecentAndNothingIsNoData() {
        #expect(resting(today: F.day(10, 24)) == .noRecent(lastDate: F.day(10, 21)))
        #expect(hrv(today: F.day(10, 24)) == .noRecent(lastDate: F.day(10, 21)))
        #expect(resting(today: F.day(10, 21), []) == .noData)
        #expect(hrv(today: F.day(10, 21), []) == .noData)
    }

    @Test func valueTextsRoundHalfAwayFromZero() {
        #expect(RecoveryFormat.hrvValueText(58.5) == "59")
        #expect(RecoveryFormat.hrvValueText(58.49) == "58")
        #expect(RecoveryFormat.restingHRValueText(48.5) == "49")
        #expect(RecoveryFormat.restingHRValueText(49) == "49")
    }

    @Test func deltaTextsUseTheRealMinusSign() {
        func comparison(_ delta: Double, _ trend: MetricTrend) -> MetricComparison {
            MetricComparison(average: 60, delta: delta, trend: trend, outcome: .neutral, countUsed: 7)
        }
        #expect(RecoveryFormat.hrvDeltaText(comparison(7.19, .up)) == "+7%")
        #expect(RecoveryFormat.hrvDeltaText(comparison(-5.5, .down)) == "\u{2212}6%")
        #expect(RecoveryFormat.restingHRDeltaText(comparison(2.5, .up)) == "+3 bpm")
        #expect(RecoveryFormat.restingHRDeltaText(comparison(-2.0, .down)) == "\u{2212}2 bpm")
        #expect(RecoveryFormat.restingHRDeltaText(comparison(-1.0, .neutral)) == "About the same")
    }
}
