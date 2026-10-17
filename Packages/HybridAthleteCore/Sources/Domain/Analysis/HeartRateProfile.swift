import Foundation

/// Heart-rate zones by heart-rate reserve (Karvonen): a boundary at fraction p
/// is rest + p x (max - rest), unrounded. Lower bounds are inclusive.
public struct HeartRateProfile: Sendable, Equatable, Codable {
    public let maxHr: Double
    public let restingHr: Double

    public init(maxHr: Double, restingHr: Double) {
        self.maxHr = maxHr
        self.restingHr = restingHr
    }

    /// Nil when either value is unknown or the reserve is not positive.
    public static func make(maxHr: Double?, restingHr: Double?) -> HeartRateProfile? {
        guard let maxHr, let restingHr, maxHr > restingHr else { return nil }
        return HeartRateProfile(maxHr: maxHr, restingHr: restingHr)
    }

    public var reserve: Double { maxHr - restingHr }

    /// rest + p x reserve.
    public func boundary(_ fraction: Double) -> Double {
        restingHr + fraction * reserve
    }

    /// 1...5: below boundary(0.60) is zone 1, below 0.70 zone 2, below 0.80
    /// zone 3, below 0.90 zone 4, otherwise zone 5.
    public func zone(for hr: Double) -> Int {
        // The tiny margin keeps 142.1 in zone 3 when 0.7 x 133 lands a hair above 93.1.
        let upperFractions = Array(AssessmentRules.zoneFractions.dropFirst())
        for (index, fraction) in upperFractions.enumerated() where hr < boundary(fraction) - 1e-9 {
            return index + 1
        }
        return 5
    }

    /// The zone's upper boundary, rounded half up (zone 2 -> boundary(0.70)).
    /// Zone 5 has none.
    public func upperBpm(zone: Int) -> Int? {
        let upperFractions = Array(AssessmentRules.zoneFractions.dropFirst())
        guard (1...upperFractions.count).contains(zone) else { return nil }
        return AnalysisMath.rounded(boundary(upperFractions[zone - 1]))
    }
}

/// The max heart rate seen in running workouts: the highest of the last 365
/// days when at least 3 runs have heart-rate data.
public enum ObservedMaxHeartRate {
    /// `maxHeartRates` are the per-run maxima of the window's runs (nil = no data).
    public static func value(_ maxHeartRates: [Double?]) -> Double? {
        let known = maxHeartRates.compactMap { $0 }.filter { $0 > 0 }
        guard known.count >= AssessmentRules.observedMaxMinRuns else { return nil }
        return known.max()
    }

    /// From the workout list: running workouts that started within the window.
    public static func value(workouts: [WorkoutSummary], now: Date) -> Double? {
        let windowStart = now.addingTimeInterval(-TimeInterval(AssessmentRules.observedMaxWindowDays) * 86_400)
        return value(workouts.filter { $0.isRun && $0.start >= windowStart && $0.start <= now }.map(\.maxHeartRate))
    }

    /// The observed max, otherwise 220 minus age, otherwise unknown.
    public static func maxHr(observed: Double?, ageYears: Int?) -> Double? {
        observed ?? ageYears.map { Double(AssessmentRules.maxHrFallbackBase - $0) }
    }
}
