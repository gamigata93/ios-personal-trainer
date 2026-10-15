import Foundation

/// Turns resting heart rate samples into one value per local day.
public enum RestingHRDayBuilder {
    public struct Result: Sendable, Equatable {
        /// Oldest first, one per date.
        public let days: [RestingHRDay]
        /// Every sample per date (all sources), for the DEBUG export. Never cached.
        public let samplesByDay: [LocalDate: [RestingHRSample]]
    }

    /// The date is the local date of each sample's end. Per date the source is
    /// `RecoveryRules.preferredSource` when present, otherwise the one with the
    /// most samples (ties alphabetical). Within it the latest sample wins.
    public static func build(_ samples: [RestingHRSample], calendar: Calendar) -> Result {
        let byDay = Dictionary(grouping: samples) { LocalDate(date: $0.endDate, calendar: calendar) }
        let days = byDay.compactMap { date, daySamples -> RestingHRDay? in
            let bySource = Dictionary(grouping: daySamples, by: \.source)
            let source = bySource.keys.contains(RecoveryRules.preferredSource)
                ? RecoveryRules.preferredSource
                : bySource.max { lhs, rhs in
                    lhs.value.count != rhs.value.count ? lhs.value.count < rhs.value.count : lhs.key > rhs.key
                }?.key
            guard let source, let latest = bySource[source]?.max(by: { $0.endDate < $1.endDate }) else { return nil }
            return RestingHRDay(date: date, bpm: latest.bpm, sourceLabel: source)
        }
        return Result(days: days.sorted { $0.date < $1.date }, samplesByDay: byDay)
    }
}
