import Foundation
import Testing
@testable import Domain

/// Hand-calculated comparisons for HRV (percent, 5% band, higher is better) and
/// resting heart rate (bpm, 2 bpm band, lower is better).
struct MetricComparisonTests {
    private func hrv(_ shown: Double, _ previous: [Double]) -> MetricComparison? {
        MetricComparison.make(
            shown: shown, previous: previous, mode: .percent,
            neutralBand: RecoveryRules.hrvNeutralPercent, direction: .higherIsBetter,
            minValues: RecoveryRules.minBaselineValues
        )
    }

    private func resting(_ shown: Double, _ previous: [Double]) -> MetricComparison? {
        MetricComparison.make(
            shown: shown, previous: previous, mode: .absolute,
            neutralBand: RecoveryRules.restingHRNeutralBpm, direction: .lowerIsBetter,
            minValues: RecoveryRules.minBaselineValues
        )
    }

    // MARK: HRV

    @Test func hrvWorkedComparison() throws {
        // Sum 431, average 61.571; (58 - 61.571) / 61.571 = -5.80%.
        let comparison = try #require(hrv(58, [62, 60, 64, 59, 61, 63, 62]))
        #expect(abs(comparison.average - 61.571_428) < 0.001)
        #expect(abs(comparison.delta - -5.800_464) < 0.001)
        #expect(comparison.trend == .down)
        #expect(comparison.outcome == .worse)
        #expect(comparison.countUsed == 7)
        #expect(RecoveryFormat.hrvDeltaText(comparison) == "\u{2212}6%")
        #expect(RecoveryFormat.hrvCaption(valuesUsed: comparison.countUsed) == "vs last 7 nights")
    }

    @Test func hrvNeutralBandEdges() throws {
        let sixty: [Double] = [60, 60, 60]
        let minusFive = try #require(hrv(57.0, sixty))
        #expect(minusFive.trend == .down)
        #expect(minusFive.outcome == .worse)
        let justInside = try #require(hrv(57.1, sixty))
        #expect(justInside.trend == .neutral)
        #expect(justInside.outcome == .neutral)
        #expect(RecoveryFormat.hrvDeltaText(justInside) == "About the same")
        let plusFive = try #require(hrv(63.0, sixty))
        #expect(plusFive.trend == .up)
        #expect(plusFive.outcome == .better)
        #expect(try #require(hrv(62.9, sixty)).trend == .neutral)
    }

    @Test func fewerThanThreePreviousValuesGiveNoComparison() throws {
        #expect(hrv(58, [60, 62]) == nil)
        let three = try #require(hrv(58, [60, 62, 61]))
        #expect(three.countUsed == 3)
        #expect(RecoveryFormat.hrvCaption(valuesUsed: three.countUsed) == "vs last 3 nights")
    }

    @Test func previousTakesTheSevenCalendarDaysBefore() {
        let shown = LocalDate(year: 2026, month: 10, day: 21)
        let dates = (12...22).map { LocalDate(year: 2026, month: 10, day: $0) }
        let previous = MetricComparison.previous(dates, date: { $0 }, before: shown, days: RecoveryRules.baselineWindow)
        #expect(previous == (14...20).map { LocalDate(year: 2026, month: 10, day: $0) })
    }

    // MARK: Resting heart rate

    private let prior: [Double] = [50, 51, 50, 52, 50, 51, 50]

    @Test func restingWorkedComparisons() throws {
        // Sum 354, average 50.571.
        let same = try #require(resting(49, prior))
        #expect(abs(same.delta - -1.571_428) < 0.001)
        #expect(same.trend == .neutral)
        #expect(RecoveryFormat.restingHRDeltaText(same) == "About the same")
        #expect(RecoveryFormat.restingHRCaption(valuesUsed: same.countUsed) == "vs last 7 days")

        let up = try #require(resting(53, prior))
        #expect(abs(up.delta - 2.428_571) < 0.001)
        #expect(up.trend == .up)
        #expect(up.outcome == .worse)
        #expect(RecoveryFormat.restingHRDeltaText(up) == "+2 bpm")

        let upMore = try #require(resting(54, prior))
        #expect(RecoveryFormat.restingHRDeltaText(upMore) == "+3 bpm")
        #expect(upMore.outcome == .worse)

        let down = try #require(resting(48, prior))
        #expect(abs(down.delta - -2.571_428) < 0.001)
        #expect(down.trend == .down)
        #expect(down.outcome == .better)
        #expect(RecoveryFormat.restingHRDeltaText(down) == "\u{2212}3 bpm")
    }

    @Test func restingNeutralBandEdges() throws {
        let fifty: [Double] = [50, 50, 50, 50, 50, 50, 50]
        let minusTwo = try #require(resting(48, fifty))
        #expect(minusTwo.delta == -2.0)
        #expect(minusTwo.trend == .down)
        #expect(minusTwo.outcome == .better)
        #expect(try #require(resting(49, fifty)).trend == .neutral)
        let plusTwo = try #require(resting(52, fifty))
        #expect(plusTwo.trend == .up)
        #expect(plusTwo.outcome == .worse)
    }
}
