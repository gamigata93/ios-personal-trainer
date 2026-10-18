import Foundation

/// Every number behind the workout assessment (zones, distance bands, the
/// observed max heart rate and auto-generation), in one place.
public enum AssessmentRules {
    /// Zone boundaries as fractions of heart-rate reserve (Karvonen): below 0.60
    /// is zone 1 (anything under 0.50 too), then 0.70, 0.80 and 0.90.
    public static let zoneFractions = [0.50, 0.60, 0.70, 0.80, 0.90]
    /// Distance within ±10% of the plan is on plan (exactly 10% included).
    public static let distanceOkBand = 0.10
    /// Distance off by MORE than 25% is off plan.
    public static let distanceOffBand = 0.25
    /// The observed max heart rate needs this many runs with heart rate...
    public static let observedMaxMinRuns = 3
    /// ...within this many days.
    public static let observedMaxWindowDays = 365
    /// Without an observed max: 220 minus age.
    public static let maxHrFallbackBase = 220
    /// Notes are written automatically for sessions from the last 7 days...
    public static let autoWindowDays = 7
    /// ...at most 3 per refresh.
    public static let maxAutoPerRefresh = 3
}

/// Every number behind the workout analysis and the facts sent to a model.
public enum AnalysisRules {
    /// First half vs second half pace within ±2% is even.
    public static let splitStyleBand = 2.0
    /// The last 2 km more than 3% slower than the rest is a fade.
    public static let fadeBand = 3.0
    /// Heart rate drift above 5% is moderate...
    public static let driftModerate = 5.0
    /// ...above 8% high.
    public static let driftHigh = 8.0
    /// Drift, split style and fade need at least 3 full splits.
    public static let driftMinSplits = 3
    /// A heart-rate sample holds until the next one, for 30 s at most.
    public static let hrSampleGapCapSeconds = 30.0
    /// Altitude is smoothed with a 5-point moving average...
    public static let altitudeSmoothingPoints = 5
    /// ...and steps under 0.5 m are ignored.
    public static let altitudeMinStepMeters = 0.5
    /// Laps come from lap or segment events when there are at least 3.
    public static let lapEventsMin = 3
    /// The facts and instructions may fill 55% of the context...
    public static let factsBudgetShare = 0.55
    /// ...minus 700 tokens kept for the answer.
    public static let outputReserveTokens = 700
    /// The context size assumed for models that do not report one.
    public static let defaultBudgetTokens = 20_000
    /// Tokens are estimated as ceil(characters / 3).
    public static let charactersPerToken = 3
    /// Recent sessions listed in the facts.
    public static let recentSessionsInFacts = 3
    /// Splits with an identical pace and heart rate that mark a flat series (diagnostic).
    public static let flatSeriesMinSplits = 4
    /// A split counts as a full kilometre from this distance on.
    public static let fullSplitKm = 0.999
    /// A partial last split shorter than this is dropped.
    public static let minPartialSplitKm = 0.01
    /// Zones with less time than this are left out of the zones finding.
    public static let minZoneSeconds = 60.0
    /// Heart-rate histogram bins are 2 bpm wide, centered on even values.
    public static let hrBinWidth = 2

    /// ceil(characters / 3).
    public static func estimatedTokens(characters: Int) -> Int {
        (characters + charactersPerToken - 1) / charactersPerToken
    }

    /// contextSize x 0.55 - 700, never negative.
    public static func factsBudget(contextSize: Int) -> Int {
        max(0, Int((Double(contextSize) * factsBudgetShare).rounded(.down)) - outputReserveTokens)
    }
}

/// Small rounding helpers shared by the analysis texts.
enum AnalysisMath {
    /// Half away from zero, with a nudge so 0.5 written as 0.4999999 still rounds up.
    static func rounded(_ value: Double) -> Int {
        Int((value + (value >= 0 ? 1e-9 : -1e-9)).rounded(.toNearestOrAwayFromZero))
    }
}
