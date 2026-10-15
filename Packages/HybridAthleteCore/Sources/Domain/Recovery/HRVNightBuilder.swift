import Foundation

/// Turns HRV samples into one mean per night, inside each night's sleep window.
public enum HRVNightBuilder {
    public struct Ignored: Sendable, Equatable, Codable {
        /// Nights whose chosen source had samples, but too few.
        public var tooFewSamples = 0

        public init(tooFewSamples: Int = 0) {
            self.tooFewSamples = tooFewSamples
        }
    }

    /// Where a night's samples are taken from.
    public struct Window: Sendable, Equatable {
        public let start: Date
        public let end: Date
        /// True for a sleep window, false for the fallback (end exclusive).
        public let includesEnd: Bool
        public let kind: HRVNight.WindowKind

        public func contains(_ date: Date) -> Bool {
            date >= start && (includesEnd ? date <= end : date < end)
        }
    }

    public struct Result: Sendable, Equatable {
        /// Oldest first, one per wake date.
        public let nights: [HRVNight]
        public let ignored: Ignored
        /// Each date's window, for the DEBUG export.
        public let windows: [LocalDate: Window]
        /// Every sample inside each date's window (all sources), for the DEBUG export. Never cached.
        public let samplesByNight: [LocalDate: [HRVSample]]
    }

    /// For each wake date from `today - queryWindowDays` to today:
    /// 1. The window is the sleep night's [sleepStart, wakeTime], or the overnight
    ///    fallback on that date when there is no sleep night.
    /// 2. The source with the most samples in the window wins; ties prefer
    ///    `RecoveryRules.preferredSource`, then the alphabetically first label.
    /// 3. Fewer than `hrvMinSamplesPerNight` samples gives no night.
    /// 4. The value is the arithmetic mean, unrounded.
    public static func build(
        samples: [HRVSample],
        sleepNights: [SleepNight],
        calendar: Calendar,
        today: LocalDate
    ) -> Result {
        let sleepByDate = Dictionary(sleepNights.map { ($0.wakeDate, $0) }, uniquingKeysWith: { first, _ in first })
        var nights: [HRVNight] = []
        var ignored = Ignored()
        var windows: [LocalDate: Window] = [:]
        var samplesByNight: [LocalDate: [HRVSample]] = [:]

        for offset in stride(from: RecoveryRules.queryWindowDays, through: 0, by: -1) {
            let date = today.adding(days: -offset)
            guard let window = window(for: date, sleep: sleepByDate[date], calendar: calendar) else { continue }
            windows[date] = window
            let inside = samples.filter { window.contains($0.date) }
            guard !inside.isEmpty else { continue }
            samplesByNight[date] = inside

            let chosen = chosenGroup(inside)
            guard chosen.samples.count >= RecoveryRules.hrvMinSamplesPerNight else {
                ignored.tooFewSamples += 1
                continue
            }
            nights.append(HRVNight(
                wakeDate: date,
                meanMs: chosen.samples.map(\.valueMs).reduce(0, +) / Double(chosen.samples.count),
                sampleCount: chosen.samples.count,
                windowKind: window.kind,
                sourceLabel: chosen.source
            ))
        }
        return Result(nights: nights, ignored: ignored, windows: windows, samplesByNight: samplesByNight)
    }

    /// The sleep window when there is a night, otherwise 00:00 to 08:00 local on `date`.
    static func window(for date: LocalDate, sleep: SleepNight?, calendar: Calendar) -> Window? {
        if let sleep {
            return Window(start: sleep.sleepStart, end: sleep.wakeTime, includesEnd: true, kind: .sleep)
        }
        guard
            let midnight = date.date(in: calendar),
            let start = calendar.date(byAdding: .hour, value: RecoveryRules.overnightFallbackStartHour, to: midnight),
            let end = calendar.date(byAdding: .hour, value: RecoveryRules.overnightFallbackEndHour, to: midnight)
        else { return nil }
        return Window(start: start, end: end, includesEnd: false, kind: .overnightFallback)
    }

    /// Most samples wins; ties prefer the preferred source, then the first label.
    private static func chosenGroup(_ samples: [HRVSample]) -> (source: String, samples: [HRVSample]) {
        let groups = Dictionary(grouping: samples, by: \.source)
        let best = groups.max { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            return RecoverySource.ranksBefore(rhs.key, lhs.key)
        }
        return best.map { ($0.key, $0.value) } ?? ("", [])
    }
}

/// Tie-breaking between sources shared by the recovery builders.
enum RecoverySource {
    /// The preferred source first, then alphabetical.
    static func ranksBefore(_ lhs: String, _ rhs: String) -> Bool {
        let preferred = RecoveryRules.preferredSource
        if (lhs == preferred) != (rhs == preferred) { return lhs == preferred }
        return lhs < rhs
    }
}
