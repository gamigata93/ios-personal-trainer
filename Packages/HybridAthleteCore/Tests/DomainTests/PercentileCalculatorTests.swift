import Foundation
import Testing
import Domain

struct PercentileCalculatorTests {
    /// Male 30-39 VO2 max row from the FRIEND table.
    private let vo2 = NormTable(
        id: "vo2", metric: .vo2max, sex: .male, ageMin: 30, ageMax: 39, unit: "ml/(kg·min)",
        anchors: [(10, 24.9), (20, 29.8), (30, 33.5), (40, 37.0), (50, 39.7), (60, 43.4), (70, 46.4), (80, 50.0), (90, 55.5)]
            .map { NormAnchor(p: $0.0, v: $0.1) },
        source: "test"
    )

    /// Male 20-39 resting heart rate row from NHANES.
    private let resting = NormTable(
        id: "rhr", metric: .restingHeartRate, sex: .male, ageMin: 20, ageMax: 39, unit: "bpm",
        anchors: [(1, 47), (2.5, 50), (5, 52), (10, 55), (25, 61), (50, 69), (75, 76), (90, 84), (95, 89), (97.5, 95), (99, 101)]
            .map { NormAnchor(p: $0.0, v: $0.1) },
        source: "test"
    )

    @Test func myVO2MaxInterpolatesBetweenEightiethAndNinetieth() throws {
        // 80 + 10 x (53.75 - 50.0) / (55.5 - 50.0) = 86.818
        let result = try #require(PercentileCalculator.result(for: 53.75, in: vo2))
        #expect(abs(result.betterThanPercent - 86.818) < 1e-3)
        #expect(result.edge == .none)
        #expect(result.band == .excellent)
    }

    @Test func myRestingHeartRateIsInverted() throws {
        // 49 bpm: 1 + 1.5 x (49 - 47) / (50 - 47) = 2.0th percentile, better than 98.
        let result = try #require(PercentileCalculator.result(for: 49, in: resting))
        #expect(abs(result.betterThanPercent - 98) < 1e-9)
        #expect(result.edge == .none)
    }

    @Test func exactlyOnAnAnchorIsNotAnEdge() throws {
        let best = try #require(PercentileCalculator.result(for: 55.5, in: vo2))
        #expect(best == PercentileResult(betterThanPercent: 90, edge: .none))
        let lowestHeartRate = try #require(PercentileCalculator.result(for: 47, in: resting))
        #expect(lowestHeartRate == PercentileResult(betterThanPercent: 99, edge: .none))
    }

    @Test func beyondTheBestAnchorIsTopEdge() throws {
        #expect(PercentileCalculator.result(for: 60, in: vo2) == PercentileResult(betterThanPercent: 90, edge: .top))
        #expect(PercentileCalculator.result(for: 40, in: resting) == PercentileResult(betterThanPercent: 99, edge: .top))
    }

    @Test func beyondTheWorstAnchorIsBottomEdge() throws {
        #expect(PercentileCalculator.result(for: 20, in: vo2) == PercentileResult(betterThanPercent: 10, edge: .bottom))
        #expect(PercentileCalculator.result(for: 110, in: resting) == PercentileResult(betterThanPercent: 1, edge: .bottom))
    }

    @Test func edgesUseTheExtremeBands() {
        #expect(PercentileResult(betterThanPercent: 90, edge: .top).band == .excellent)
        #expect(PercentileResult(betterThanPercent: 10, edge: .bottom).band == .low)
    }

    @Test(arguments: [
        (19.99, FitnessBand.low), (20, .belowAverage), (39.99, .belowAverage), (40, .average),
        (59.99, .average), (60, .aboveAverage), (79.99, .aboveAverage), (80, .excellent),
    ])
    func bandBoundaries(betterThan: Double, band: FitnessBand) {
        #expect(PercentileResult(betterThanPercent: betterThan, edge: .none).band == band)
    }
}
