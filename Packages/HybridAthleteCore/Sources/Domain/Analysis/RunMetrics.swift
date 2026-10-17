import Foundation

/// Seconds per heart-rate zone, from the histogram (each bin by its center).
public enum ZoneTime {
    /// Index 0 is zone 1.
    public static func seconds(_ analysis: WorkoutAnalysis, profile: HeartRateProfile) -> [Double] {
        var zones = [Double](repeating: 0, count: 5)
        for bin in analysis.hrHistogram {
            zones[profile.zone(for: Double(bin.centerBpm)) - 1] += bin.seconds
        }
        return zones
    }
}

/// Only easy and long runs are judged on drift, split style and fade.
extension SessionType {
    public var hasSteadyEffort: Bool { self == .easy || self == .long }
}

/// Heart rate drift: the last third of the splits against the first third.
public struct HeartRateDrift: Sendable, Equatable {
    public enum Band: String, Sendable, Equatable {
        case low, moderate, high
    }

    /// (last - first) / first, in percent.
    public let percent: Double
    public let band: Band

    /// Easy and long sessions with at least 3 full splits that all have heart
    /// rate: k = max(1, floor(n / 3)) splits at each end.
    public static func measure(_ analysis: WorkoutAnalysis, type: SessionType) -> HeartRateDrift? {
        let splits = analysis.fullSplits
        guard type.hasSteadyEffort, splits.count >= AnalysisRules.driftMinSplits else { return nil }
        let rates = splits.compactMap(\.avgHr)
        guard rates.count == splits.count else { return nil }
        let k = max(1, rates.count / 3)
        let first = rates.prefix(k).reduce(0, +) / Double(k)
        let last = rates.suffix(k).reduce(0, +) / Double(k)
        guard first > 0 else { return nil }
        let percent = (last - first) / first * 100
        return HeartRateDrift(percent: percent, band: band(percent))
    }

    /// <= 5 low, <= 8 moderate, above that high.
    public static func band(_ percent: Double) -> Band {
        if percent <= AnalysisRules.driftModerate + 1e-9 { return .low }
        if percent <= AnalysisRules.driftHigh + 1e-9 { return .moderate }
        return .high
    }
}

/// First half of the splits against the second half (by count; an odd middle split is left out).
public struct SplitStyle: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case even, negative, positive
    }

    public let kind: Kind
    public let firstHalfPace: Double
    public let secondHalfPace: Double

    /// Second minus first, seconds per km.
    public var deltaSecPerKm: Double { secondHalfPace - firstHalfPace }

    public static func measure(_ analysis: WorkoutAnalysis, type: SessionType) -> SplitStyle? {
        let paces = analysis.fullSplits.map(\.paceSecPerKm)
        guard type.hasSteadyEffort, paces.count >= AnalysisRules.driftMinSplits else { return nil }
        let half = paces.count / 2
        let first = paces.prefix(half).reduce(0, +) / Double(half)
        let second = paces.suffix(half).reduce(0, +) / Double(half)
        return SplitStyle(kind: kind(first: first, second: second), firstHalfPace: first, secondHalfPace: second)
    }

    /// |delta| <= 2% even; second half faster by more than 2% negative; slower positive.
    public static func kind(first: Double, second: Double) -> Kind {
        guard first > 0 else { return .even }
        let percent = (second - first) / first * 100
        if abs(percent) <= AnalysisRules.splitStyleBand + 1e-9 { return .even }
        return percent < 0 ? .negative : .positive
    }
}

/// The last 2 km against everything before them.
public struct Fade: Sendable, Equatable {
    /// Slower by this much, seconds per km.
    public let slowerSecPerKm: Double

    /// Nil when the last 2 splits are not more than 3% slower.
    public static func measure(_ analysis: WorkoutAnalysis, type: SessionType) -> Fade? {
        let paces = analysis.fullSplits.map(\.paceSecPerKm)
        guard type.hasSteadyEffort, paces.count >= AnalysisRules.driftMinSplits else { return nil }
        let last = paces.suffix(2).reduce(0, +) / 2
        let earlier = paces.dropLast(2)
        let before = earlier.reduce(0, +) / Double(earlier.count)
        guard before > 0, (last - before) / before * 100 > AnalysisRules.fadeBand + 1e-9 else { return nil }
        return Fade(slowerSecPerKm: last - before)
    }
}
