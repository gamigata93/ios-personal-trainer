import Foundation

/// Which night the Sleep card shows.
public enum SleepSelection: Sendable, Equatable {
    /// "Last night", "Yesterday" or "Mon 26 Oct".
    case shown(SleepNight, label: String)
    /// Nights exist, but none woke within the last `SleepRules.maxAgeDays` days.
    case noRecent(lastWakeDate: LocalDate)
    case noData

    /// The newest night that woke today or up to `maxAgeDays` days before.
    public static func select(nights: [SleepNight], today: LocalDate) -> SleepSelection {
        switch RecentSelection.select(nights, date: \.wakeDate, today: today, maxAgeDays: SleepRules.maxAgeDays, label: label(for:today:)) {
        case .shown(let night, let label): .shown(night, label: label)
        case .noRecent(let last): .noRecent(lastWakeDate: last)
        case .noData: .noData
        }
    }

    static func label(for wakeDate: LocalDate, today: LocalDate) -> String {
        switch wakeDate.days(to: today) {
        case 0: "Last night"
        case 1: "Yesterday"
        default: HomeFormat.shortDate(wakeDate)
        }
    }
}

/// Up, down or about the same as the previous nights.
public typealias SleepTrend = MetricTrend

extension MetricTrend {
    /// Sleep's band: neutral inside ±`SleepRules.neutralDeltaPercent` (exclusive); exactly 3% is a change.
    public static func of(deltaPercent: Double) -> MetricTrend {
        of(delta: deltaPercent, band: SleepRules.neutralDeltaPercent)
    }
}

/// The shown night against the nights before it, through `MetricComparison`.
public struct SleepComparison: Sendable, Equatable {
    public let averageMinutes: Double
    /// Unrounded.
    public let deltaPercent: Double
    public let trend: SleepTrend
    public let nightsUsed: Int

    public init(averageMinutes: Double, deltaPercent: Double, trend: SleepTrend, nightsUsed: Int) {
        self.averageMinutes = averageMinutes
        self.deltaPercent = deltaPercent
        self.trend = trend
        self.nightsUsed = nightsUsed
    }

    /// Nights waking in the `SleepRules.baselineNights` calendar days before the
    /// shown night. Nil with fewer than `SleepRules.minBaselineNights`.
    public static func make(shown: SleepNight, nights: [SleepNight]) -> SleepComparison? {
        let previous = MetricComparison.previous(nights, date: \.wakeDate, before: shown.wakeDate, days: SleepRules.baselineNights)
        guard let metric = MetricComparison.make(
            shown: Double(shown.asleepMinutes),
            previous: previous.map { Double($0.asleepMinutes) },
            mode: .percent,
            neutralBand: SleepRules.neutralDeltaPercent,
            direction: .higherIsBetter,
            minValues: SleepRules.minBaselineNights
        ) else { return nil }
        return SleepComparison(averageMinutes: metric.average, deltaPercent: metric.delta, trend: metric.trend, nightsUsed: metric.countUsed)
    }

    public static func deltaPercent(shown: Double, average: Double) -> Double {
        (shown - average) / average * 100
    }
}

/// Plain English sleep text. Pure and locale-independent.
public enum SleepFormat {
    /// 450 "7h 30m", 480 "8h", 45 "45m", 0 "0m".
    public static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// "7 hours 30 minutes", for VoiceOver.
    public static func spokenDuration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if rest > 0 || hours == 0 { parts.append(rest == 1 ? "1 minute" : "\(rest) minutes") }
        return parts.joined(separator: " ")
    }

    /// Whole percent, rounded half away from zero: "+7%", "−14%" (U+2212), or
    /// "About the same" when neutral.
    public static func deltaText(_ comparison: SleepComparison) -> String {
        guard comparison.trend != .neutral else { return "About the same" }
        let rounded = Int(comparison.deltaPercent.rounded(.toNearestOrAwayFromZero))
        return rounded >= 0 ? "+\(rounded)%" : "\u{2212}\(abs(rounded))%"
    }

    /// "7 percent above your last 7 nights", for VoiceOver.
    public static func spokenDelta(_ comparison: SleepComparison) -> String {
        let nights = nightsPhrase(comparison.nightsUsed)
        guard comparison.trend != .neutral else { return "About the same as \(nights)" }
        let rounded = abs(Int(comparison.deltaPercent.rounded(.toNearestOrAwayFromZero)))
        return "\(rounded) percent \(comparison.trend == .up ? "above" : "below") \(nights)"
    }

    /// "vs your last 7 nights", or "vs your last 3 nights" with fewer.
    public static func comparisonCaption(nightsUsed: Int) -> String {
        "vs \(nightsPhrase(nightsUsed))"
    }

    private static func nightsPhrase(_ count: Int) -> String {
        "your last \(min(count, SleepRules.baselineNights)) nights"
    }
}
