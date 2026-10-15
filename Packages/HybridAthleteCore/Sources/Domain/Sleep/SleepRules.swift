import Foundation

/// Every number the sleep rules use. Change them here only.
public enum SleepRules {
    /// A gap strictly longer than this between one segment's end and the next
    /// segment's start (same source) splits a session.
    public static let sessionGapMinutes = 60
    /// A session with less sleep than this that ends between `napWindowStartHour`
    /// and `napWindowEndHour` local time is a nap and ignored.
    public static let napMaxAsleepMinutes = 90
    /// Nap wake times: from 09:00 up to (not including) 20:00 local.
    public static let napWindowStartHour = 9
    public static let napWindowEndHour = 20
    /// Sessions that are not naps but have less sleep than this are ignored as too short.
    public static let minNightAsleepMinutes = 120
    /// The comparison uses the nights in this many calendar days before the shown night.
    public static let baselineNights = 7
    /// Fewer previous nights than this means no comparison.
    public static let minBaselineNights = 3
    /// |delta| below this percentage reads "About the same".
    public static let neutralDeltaPercent = 3.0
    /// A night is recent when its wake date is at most this many days before today.
    public static let maxAgeDays = 2
    /// The Health query starts at local noon this many days before today.
    public static let queryWindowDays = 15
    /// The query window starts at this local hour.
    public static let queryWindowStartHour = 12
    /// The cache keeps the newest nights by wake date.
    public static let cachedNights = 16
    /// Wins a tie between sources for the same night.
    public static let preferredSource = "Apple Watch"
}
