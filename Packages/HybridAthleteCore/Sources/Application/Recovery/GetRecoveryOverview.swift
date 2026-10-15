import Foundation
import Domain

/// One compact recovery card's content, already worded.
public struct RecoveryMetricOverview: Sendable, Equatable {
    /// "58".
    public let valueText: String
    /// "ms" or "bpm".
    public let unit: String
    /// "Last night", "Today", "Yesterday" or "Mon 26 Oct".
    public let label: String
    public let comparison: MetricComparison?
    /// "−6%", "+2 bpm" or "About the same".
    public let deltaText: String?
    /// "vs last 7 nights" or "vs last 7 days".
    public let caption: String?
    /// The whole card as one sentence for VoiceOver.
    public let accessibilityLabel: String
}

/// What one compact card shows for a set of values.
public enum RecoveryMetricState: Sendable, Equatable {
    case ready(RecoveryMetricOverview)
    case noRecent(lastDate: LocalDate)
    case noData
}

public struct RecoveryCardsState: Sendable, Equatable {
    public let hrv: RecoveryMetricState
    public let restingHr: RecoveryMetricState
}

/// Picks the shown HRV night and resting heart rate day and compares each with
/// the days before, using the Domain recovery rules.
public struct GetRecoveryOverview: Sendable {
    public init() {}

    public func execute(hrv: [HRVNight], restingHr: [RestingHRDay], today: LocalDate) -> RecoveryCardsState {
        RecoveryCardsState(hrv: hrvState(hrv, today: today), restingHr: restingHRState(restingHr, today: today))
    }

    public func hrvState(_ nights: [HRVNight], today: LocalDate) -> RecoveryMetricState {
        let selection = RecentSelection.select(
            nights, date: \.wakeDate, today: today, maxAgeDays: RecoveryRules.maxAgeDays, label: RecoveryLabel.night
        )
        switch selection {
        case .noData: return .noData
        case .noRecent(let last): return .noRecent(lastDate: last)
        case .shown(let night, let label):
            let previous = MetricComparison.previous(nights, date: \.wakeDate, before: night.wakeDate, days: RecoveryRules.baselineWindow)
            let comparison = MetricComparison.make(
                shown: night.meanMs,
                previous: previous.map(\.meanMs),
                mode: .percent,
                neutralBand: RecoveryRules.hrvNeutralPercent,
                direction: .higherIsBetter,
                minValues: RecoveryRules.minBaselineValues
            )
            let value = RecoveryFormat.hrvValueText(night.meanMs)
            var spoken = "Heart rate variability, \(Self.spokenLabel(label)). \(value) milliseconds"
            spoken += comparison.map { ", \(RecoveryFormat.spokenHRVDelta($0))." } ?? "."
            return .ready(RecoveryMetricOverview(
                valueText: value,
                unit: "ms",
                label: label,
                comparison: comparison,
                deltaText: comparison.map(RecoveryFormat.hrvDeltaText),
                caption: comparison.map { RecoveryFormat.hrvCaption(valuesUsed: $0.countUsed) },
                accessibilityLabel: spoken
            ))
        }
    }

    public func restingHRState(_ days: [RestingHRDay], today: LocalDate) -> RecoveryMetricState {
        let selection = RecentSelection.select(
            days, date: \.date, today: today, maxAgeDays: RecoveryRules.maxAgeDays, label: RecoveryLabel.day
        )
        switch selection {
        case .noData: return .noData
        case .noRecent(let last): return .noRecent(lastDate: last)
        case .shown(let day, let label):
            let previous = MetricComparison.previous(days, date: \.date, before: day.date, days: RecoveryRules.baselineWindow)
            let comparison = MetricComparison.make(
                shown: day.bpm,
                previous: previous.map(\.bpm),
                mode: .absolute,
                neutralBand: RecoveryRules.restingHRNeutralBpm,
                direction: .lowerIsBetter,
                minValues: RecoveryRules.minBaselineValues
            )
            let value = RecoveryFormat.restingHRValueText(day.bpm)
            var spoken = "Resting heart rate, \(Self.spokenLabel(label)). \(value) beats per minute"
            spoken += comparison.map { ", \(RecoveryFormat.spokenRestingHRDelta($0))." } ?? "."
            return .ready(RecoveryMetricOverview(
                valueText: value,
                unit: "bpm",
                label: label,
                comparison: comparison,
                deltaText: comparison.map(RecoveryFormat.restingHRDeltaText),
                caption: comparison.map { RecoveryFormat.restingHRCaption(valuesUsed: $0.countUsed) },
                accessibilityLabel: spoken
            ))
        }
    }

    /// "last night", "today", "yesterday"; dates stay as written.
    private static func spokenLabel(_ label: String) -> String {
        ["Last night", "Today", "Yesterday"].contains(label) ? label.lowercased() : label
    }
}
