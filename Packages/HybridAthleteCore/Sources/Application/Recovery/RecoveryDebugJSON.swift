#if DEBUG
import Foundation
import Domain

/// DEBUG only. The HRV and resting heart rate reads as pretty JSON, so real
/// data can be sent back for review: the window, sample counts per source,
/// every summary, the shown night's and day's samples and what was ignored.
/// Dates are ISO-8601 in UTC.
public enum RecoveryDebugJSON {
    /// `sdkHasRmssdType`: whether this HealthKit build exposes an RMSSD type. A
    /// diagnostic only; RMSSD is never read.
    public static func string(hrv: HRVRead?, restingHr: RestingHRRead?, sdkHasRmssdType: Bool) -> String {
        let readAt = [hrv?.readAt, restingHr?.readAt].compactMap { $0 }.max() ?? Date(timeIntervalSince1970: 0)
        let calendar = hrv?.calendar ?? restingHr?.calendar ?? Calendar(identifier: .gregorian)
        let window = hrv?.window ?? restingHr?.window
        let today = LocalDate(date: readAt, calendar: calendar)

        let shownHrv: ShownHRV? = hrv.flatMap { read in
            let nights = read.build.nights
            guard case .shown(let night, _) = RecentSelection.select(
                nights, date: \.wakeDate, today: today, maxAgeDays: RecoveryRules.maxAgeDays, label: RecoveryLabel.night
            ) else { return nil }
            return ShownHRV(
                wakeDate: night.wakeDate.description,
                windowKind: night.windowKind.rawValue,
                samples: (read.build.samplesByNight[night.wakeDate] ?? []).map { HRVPoint(time: $0.date, ms: $0.valueMs, source: $0.source) }
            )
        }
        let shownResting: ShownRestingHR? = restingHr.flatMap { read in
            guard case .shown(let day, _) = RecentSelection.select(
                read.build.days, date: \.date, today: today, maxAgeDays: RecoveryRules.maxAgeDays, label: RecoveryLabel.day
            ) else { return nil }
            return ShownRestingHR(
                date: day.date.description,
                samples: (read.build.samplesByDay[day.date] ?? [])
                    .sorted { $0.endDate < $1.endDate }
                    .map { RestingPoint(endTime: $0.endDate, bpm: $0.bpm, source: $0.source) }
            )
        }

        let export = Export(
            generatedAt: readAt,
            timeZone: calendar.timeZone.identifier,
            window: window.map { Window(from: $0.start, to: $0.end) },
            sourcesInWindow: Sources(
                hrv: Dictionary(grouping: hrv?.samples ?? [], by: \.source).mapValues(\.count),
                restingHr: Dictionary(grouping: restingHr?.samples ?? [], by: \.source).mapValues(\.count)
            ),
            hrvNights: hrv?.build.nights ?? [],
            restingHrDays: restingHr?.build.days ?? [],
            shownHrv: shownHrv,
            shownRestingHr: shownResting,
            ignored: hrv?.build.ignored ?? HRVNightBuilder.Ignored(),
            sdkHasRmssdType: sdkHasRmssdType
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(export)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private struct Export: Encodable {
        let generatedAt: Date
        let timeZone: String
        let window: Window?
        let sourcesInWindow: Sources
        let hrvNights: [HRVNight]
        let restingHrDays: [RestingHRDay]
        let shownHrv: ShownHRV?
        let shownRestingHr: ShownRestingHR?
        let ignored: HRVNightBuilder.Ignored
        let sdkHasRmssdType: Bool
    }

    private struct Window: Encodable {
        let from: Date
        let to: Date
    }

    private struct Sources: Encodable {
        let hrv: [String: Int]
        let restingHr: [String: Int]
    }

    private struct ShownHRV: Encodable {
        let wakeDate: String
        let windowKind: String
        let samples: [HRVPoint]
    }

    private struct HRVPoint: Encodable {
        let time: Date
        let ms: Double
        let source: String
    }

    private struct ShownRestingHR: Encodable {
        let date: String
        let samples: [RestingPoint]
    }

    private struct RestingPoint: Encodable {
        let endTime: Date
        let bpm: Double
        let source: String
    }
}
#endif
