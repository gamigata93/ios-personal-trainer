import Foundation
@testable import Domain

/// A fixed UTC+3 zone (no DST) and builders for sleep tests.
enum SleepFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 10_800) ?? .gmt
        return calendar
    }()

    /// "2026-10-20", "23:15" in UTC+3.
    static func local(_ date: String, _ time: String) -> Date {
        let day = LocalDate(date) ?? LocalDate(year: 1970, month: 1, day: 1)
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: parts[0], minute: parts[1])) ?? .distantPast
    }

    static func segment(_ stage: SleepStage, _ start: (String, String), _ end: (String, String), source: String = "Apple Watch") -> SleepSegment {
        SleepSegment(start: local(start.0, start.1), end: local(end.0, end.1), stage: stage, source: source)
    }

    /// The worked night ending Wed 21 Oct 2026 at 06:50: 450 asleep, 5 awake.
    static func workedNight(source: String = "Apple Watch") -> [SleepSegment] {
        let a = "2026-10-20", b = "2026-10-21"
        return [
            segment(.core, (a, "23:15"), (b, "00:45"), source: source),
            segment(.deep, (b, "00:45"), (b, "01:30"), source: source),
            segment(.core, (b, "01:30"), (b, "03:00"), source: source),
            segment(.rem, (b, "03:00"), (b, "03:50"), source: source),
            segment(.awake, (b, "03:50"), (b, "03:55"), source: source),
            segment(.core, (b, "03:55"), (b, "05:30"), source: source),
            segment(.deep, (b, "05:30"), (b, "06:00"), source: source),
            segment(.rem, (b, "06:00"), (b, "06:50"), source: source),
        ]
    }

    /// A summary with only the fields the selection and comparison read.
    static func night(_ wakeDate: LocalDate, asleep: Int) -> SleepNight {
        let wake = local(wakeDate.description, "06:50")
        return SleepNight(
            wakeDate: wakeDate, sleepStart: wake.addingTimeInterval(-Double(asleep * 60)), wakeTime: wake,
            asleepMinutes: asleep, deepMinutes: 0, coreMinutes: asleep, remMinutes: 0, unspecifiedMinutes: 0,
            awakeMinutes: 0, timeInBedMinutes: asleep, hasStages: true, sourceLabel: "Apple Watch"
        )
    }

    static func day(_ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: 2026, month: month, day: day)
    }
}
