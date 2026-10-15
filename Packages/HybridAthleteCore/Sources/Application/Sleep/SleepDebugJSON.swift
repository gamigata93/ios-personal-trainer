#if DEBUG
import Foundation
import Domain

/// DEBUG only. The sleep read as pretty JSON, so real data can be sent back for
/// review: the window, segment counts per source, every night, the shown
/// night's segments and what was ignored. Dates are ISO-8601 in UTC.
public enum SleepDebugJSON {
    public static func string(read: SleepRead) -> String {
        let now = read.readAt
        let calendar = read.calendar
        let today = LocalDate(date: now, calendar: calendar)
        let shown: ShownNight? = {
            guard case .shown(let night, _) = SleepSelection.select(nights: read.build.nights, today: today) else { return nil }
            return ShownNight(
                wakeDate: night.wakeDate.description,
                segments: (read.build.segmentsByNight[night.wakeDate] ?? []).map(Segment.init)
            )
        }()
        let export = Export(
            generatedAt: now,
            timeZone: calendar.timeZone.identifier,
            window: Window(from: read.window.start, to: read.window.end),
            sourcesInWindow: Dictionary(grouping: read.segments, by: \.source).mapValues(\.count),
            nights: read.build.nights,
            shownNight: shown,
            ignored: read.build.ignored
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(export)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private struct Export: Encodable {
        let generatedAt: Date
        let timeZone: String
        let window: Window
        let sourcesInWindow: [String: Int]
        let nights: [SleepNight]
        let shownNight: ShownNight?
        let ignored: SleepNightBuilder.Ignored
    }

    private struct Window: Encodable {
        let from: Date
        let to: Date
    }

    private struct ShownNight: Encodable {
        let wakeDate: String
        let segments: [Segment]
    }

    private struct Segment: Encodable {
        let start: Date
        let end: Date
        let stage: String
        let source: String

        init(_ segment: SleepSegment) {
            start = segment.start
            end = segment.end
            stage = segment.stage.rawValue
            source = segment.source
        }
    }
}
#endif
