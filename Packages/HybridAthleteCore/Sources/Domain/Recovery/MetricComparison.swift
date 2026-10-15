import Foundation

/// Up, down or about the same as the previous values (the numeric direction).
public enum MetricTrend: String, Sendable, Equatable, Codable {
    case up, down, neutral

    /// Neutral inside ±`band` (exclusive): exactly the band is a change.
    public static func of(delta: Double, band: Double) -> MetricTrend {
        // A hair of tolerance so a computed edge value never falls just inside the band.
        let edge = band - 1e-9
        if delta >= edge { return .up }
        if delta <= -edge { return .down }
        return .neutral
    }
}

/// Whether a change is good news. Status colors follow this, never the direction.
public enum MetricOutcome: String, Sendable, Equatable, Codable {
    case better, worse, neutral
}

/// One value against the same kind of values from the days before it.
public struct MetricComparison: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        /// (shown - average) / average * 100.
        case percent
        /// shown - average, in the value's unit.
        case absolute
    }

    public enum Direction: Sendable, Equatable {
        case higherIsBetter, lowerIsBetter
    }

    public let average: Double
    /// Unrounded, in percent or in the value's unit.
    public let delta: Double
    public let trend: MetricTrend
    public let outcome: MetricOutcome
    public let countUsed: Int

    /// Nil with fewer than `minValues` previous values, or a zero average in percent mode.
    public static func make(
        shown: Double,
        previous: [Double],
        mode: Mode,
        neutralBand: Double,
        direction: Direction,
        minValues: Int
    ) -> MetricComparison? {
        guard previous.count >= minValues, !previous.isEmpty else { return nil }
        let average = previous.reduce(0, +) / Double(previous.count)
        let delta: Double
        switch mode {
        case .percent:
            guard average > 0 else { return nil }
            delta = (shown - average) / average * 100
        case .absolute:
            delta = shown - average
        }
        let trend = MetricTrend.of(delta: delta, band: neutralBand)
        let outcome: MetricOutcome = switch (trend, direction) {
        case (.neutral, _): .neutral
        case (.up, .higherIsBetter), (.down, .lowerIsBetter): .better
        case (.up, .lowerIsBetter), (.down, .higherIsBetter): .worse
        }
        return MetricComparison(average: average, delta: delta, trend: trend, outcome: outcome, countUsed: previous.count)
    }

    /// The items dated in the `days` calendar days before `shown` (not `shown` itself).
    public static func previous<Item>(_ items: [Item], date: (Item) -> LocalDate, before shown: LocalDate, days: Int) -> [Item] {
        let first = shown.adding(days: -days)
        return items.filter { date($0) >= first && date($0) < shown }
    }
}
