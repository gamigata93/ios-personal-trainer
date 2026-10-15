import Foundation

/// Every number the HRV and resting heart rate rules use. Change them here only.
public enum RecoveryRules {
    /// A night needs at least this many HRV samples from the chosen source.
    public static let hrvMinSamplesPerNight = 2
    /// HRV |delta| below this percentage reads "About the same".
    public static let hrvNeutralPercent = 5.0
    /// Resting heart rate |delta| below this many bpm reads "About the same".
    public static let restingHRNeutralBpm = 2.0
    /// The comparison uses the values in this many calendar days before the shown date.
    public static let baselineWindow = 7
    /// Fewer previous values than this means no comparison.
    public static let minBaselineValues = 3
    /// A value is recent when its date is at most this many days before today.
    public static let maxAgeDays = 2
    /// The Health query starts at local noon this many days before today (as sleep).
    public static let queryWindowDays = 15
    /// The query window starts at this local hour.
    public static let queryWindowStartHour = 12
    /// Without a sleep night, HRV is taken from this local hour (inclusive)...
    public static let overnightFallbackStartHour = 0
    /// ...up to this local hour (exclusive).
    public static let overnightFallbackEndHour = 8
    /// The cache keeps the newest entries by date, per metric.
    public static let cachedEntries = 16
    /// Wins a tie between sources.
    public static let preferredSource = "Apple Watch"
}
