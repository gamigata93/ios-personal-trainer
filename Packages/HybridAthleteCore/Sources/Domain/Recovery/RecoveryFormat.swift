import Foundation

/// Plain English HRV and resting heart rate text. Pure and locale-independent.
public enum RecoveryFormat {
    /// Whole milliseconds, half away from zero: 58.5 "59".
    public static func hrvValueText(_ meanMs: Double) -> String {
        "\(Int(meanMs.rounded(.toNearestOrAwayFromZero)))"
    }

    /// Whole beats per minute, half away from zero.
    public static func restingHRValueText(_ bpm: Double) -> String {
        "\(Int(bpm.rounded(.toNearestOrAwayFromZero)))"
    }

    /// "+7%", "−6%" (U+2212), or "About the same".
    public static func hrvDeltaText(_ comparison: MetricComparison) -> String {
        signed(comparison, suffix: "%")
    }

    /// "+2 bpm", "−3 bpm" (U+2212), or "About the same".
    public static func restingHRDeltaText(_ comparison: MetricComparison) -> String {
        signed(comparison, suffix: " bpm")
    }

    /// "vs last 7 nights".
    public static func hrvCaption(valuesUsed: Int) -> String {
        "vs last \(valuesUsed) \(valuesUsed == 1 ? "night" : "nights")"
    }

    /// "vs last 7 days".
    public static func restingHRCaption(valuesUsed: Int) -> String {
        "vs last \(valuesUsed) \(valuesUsed == 1 ? "day" : "days")"
    }

    /// "6 percent below your last 7 nights", for VoiceOver.
    public static func spokenHRVDelta(_ comparison: MetricComparison) -> String {
        spoken(comparison, unit: { "\($0) percent" }, period: "your last \(comparison.countUsed) nights")
    }

    /// "3 beats per minute below your last 7 days", for VoiceOver.
    public static func spokenRestingHRDelta(_ comparison: MetricComparison) -> String {
        spoken(comparison, unit: { $0 == 1 ? "1 beat per minute" : "\($0) beats per minute" }, period: "your last \(comparison.countUsed) days")
    }

    private static func signed(_ comparison: MetricComparison, suffix: String) -> String {
        guard comparison.trend != .neutral else { return "About the same" }
        let rounded = Int(comparison.delta.rounded(.toNearestOrAwayFromZero))
        return rounded >= 0 ? "+\(rounded)\(suffix)" : "\u{2212}\(abs(rounded))\(suffix)"
    }

    private static func spoken(_ comparison: MetricComparison, unit: (Int) -> String, period: String) -> String {
        guard comparison.trend != .neutral else { return "about the same as \(period)" }
        let rounded = abs(Int(comparison.delta.rounded(.toNearestOrAwayFromZero)))
        return "\(unit(rounded)) \(comparison.trend == .up ? "above" : "below") \(period)"
    }
}
