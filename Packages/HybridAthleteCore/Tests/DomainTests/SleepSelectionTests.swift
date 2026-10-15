import Foundation
import Testing
@testable import Domain

struct SleepSelectionTests {
    private typealias F = SleepFixtures

    private var worked: SleepNight {
        SleepNightBuilder.build(F.workedNight(), calendar: F.calendar).nights[0]
    }

    @Test func labelsFollowToday() {
        #expect(SleepSelection.select(nights: [worked], today: F.day(10, 21)) == .shown(worked, label: "Last night"))
        #expect(SleepSelection.select(nights: [worked], today: F.day(10, 22)) == .shown(worked, label: "Yesterday"))
        #expect(SleepSelection.select(nights: [worked], today: F.day(10, 23)) == .shown(worked, label: "Wed 21 Oct"))
    }

    @Test func olderThanTwoDaysIsNotRecent() {
        #expect(SleepSelection.select(nights: [worked], today: F.day(10, 24)) == .noRecent(lastWakeDate: F.day(10, 21)))
    }

    @Test func noNightsIsNoData() {
        #expect(SleepSelection.select(nights: [], today: F.day(10, 21)) == .noData)
    }

    // MARK: Comparison

    private let previous = [420, 400, 450, 380, 460, 430, 410] // 14 to 20 Oct

    @Test func comparisonWithSevenNights() throws {
        let nights = previous.enumerated().map { F.night(F.day(10, 14 + $0.offset), asleep: $0.element) } + [worked]
        let comparison = try #require(SleepComparison.make(shown: worked, nights: nights))
        // 2950 / 7 = 421.43; (450 - 421.43) / 421.43 = +6.78%.
        #expect(abs(comparison.averageMinutes - 421.428_571) < 0.001)
        #expect(abs(comparison.deltaPercent - 6.779_661) < 0.001)
        #expect(comparison.trend == .up)
        #expect(comparison.nightsUsed == 7)
        #expect(SleepFormat.deltaText(comparison) == "+7%")
        #expect(SleepFormat.comparisonCaption(nightsUsed: comparison.nightsUsed) == "vs your last 7 nights")
    }

    @Test func nightsOutsideTheSevenDaysAreLeftOut() throws {
        let nights = [F.night(F.day(10, 13), asleep: 100)]
            + previous.enumerated().map { F.night(F.day(10, 14 + $0.offset), asleep: $0.element) }
        #expect(try #require(SleepComparison.make(shown: worked, nights: nights)).nightsUsed == 7)
    }

    private func comparison(shown: Int, average: Int) -> SleepComparison? {
        let nights = (1...7).map { F.night(F.day(10, 21 - $0), asleep: average) }
        return SleepComparison.make(shown: F.night(F.day(10, 21), asleep: shown), nights: nights)
    }

    @Test func theNeutralBand() throws {
        let same = try #require(comparison(shown: 444, average: 432)) // +2.78%
        #expect(same.trend == .neutral)
        #expect(SleepFormat.deltaText(same) == "About the same")

        let up = try #require(comparison(shown: 445, average: 432)) // +3.007%
        #expect(up.trend == .up)
        #expect(SleepFormat.deltaText(up) == "+3%")

        let down = try #require(comparison(shown: 372, average: 432)) // -13.89%
        #expect(down.trend == .down)
        #expect(SleepFormat.deltaText(down) == "\u{2212}14%")
    }

    @Test func exactlyThreePercentIsNotNeutral() {
        // 432 x 1.03 = 444.96.
        let delta = SleepComparison.deltaPercent(shown: 444.96, average: 432)
        #expect(SleepTrend.of(deltaPercent: delta) == .up)
        #expect(SleepTrend.of(deltaPercent: -3.0) == .down)
    }

    @Test func fewerThanThreeNightsHaveNoComparison() throws {
        let two = [F.night(F.day(10, 19), asleep: 400), F.night(F.day(10, 20), asleep: 400)]
        #expect(SleepComparison.make(shown: worked, nights: two) == nil)

        let three = two + [F.night(F.day(10, 18), asleep: 400)]
        let comparison = try #require(SleepComparison.make(shown: worked, nights: three))
        #expect(comparison.nightsUsed == 3)
        #expect(SleepFormat.comparisonCaption(nightsUsed: 3) == "vs your last 3 nights")
    }

    // MARK: Formatting

    @Test(arguments: [(450, "7h 30m"), (372, "6h 12m"), (480, "8h"), (45, "45m"), (0, "0m")])
    func durations(minutes: Int, expected: String) {
        #expect(SleepFormat.durationText(minutes: minutes) == expected)
    }

    @Test func deltaRoundsHalfAwayFromZero() {
        func text(_ delta: Double) -> String {
            SleepFormat.deltaText(SleepComparison(averageMinutes: 400, deltaPercent: delta, trend: .of(deltaPercent: delta), nightsUsed: 7))
        }
        #expect(text(6.5) == "+7%")
        #expect(text(-6.5) == "\u{2212}7%")
        #expect(text(-13.89) == "\u{2212}14%")
        #expect(text(4.49) == "+4%")
    }

    @Test func spokenDurations() {
        #expect(SleepFormat.spokenDuration(minutes: 450) == "7 hours 30 minutes")
        #expect(SleepFormat.spokenDuration(minutes: 60) == "1 hour")
        #expect(SleepFormat.spokenDuration(minutes: 5) == "5 minutes")
    }
}
