import Foundation
import Domain

/// The Sleep card's content for a set of nights.
public enum SleepCardState: Sendable, Equatable {
    case ready(SleepOverview)
    case noRecent(lastWakeDate: LocalDate)
    case noData
}

public struct SleepOverview: Sendable, Equatable {
    public struct Stage: Sendable, Equatable, Identifiable {
        public enum Kind: String, Sendable, Equatable {
            case deep, core, rem, awake
        }

        public var id: Kind { kind }
        public let kind: Kind
        /// "Deep", "Core", "REM", "Awake".
        public let name: String
        public let minutes: Int
        /// "1h 15m".
        public let durationText: String
    }

    /// "Last night", "Yesterday" or "Mon 26 Oct".
    public let label: String
    public let night: SleepNight
    /// "7h 30m".
    public let durationText: String
    /// "23:15 – 06:50" in the device's time format.
    public let windowText: String
    public let comparison: SleepComparison?
    /// "+7%", "−14%" or "About the same".
    public let deltaText: String?
    /// "vs your last 7 nights".
    public let comparisonCaption: String?
    /// Deep, core, REM and awake of at least 1 minute; empty without stages.
    public let stages: [Stage]
    /// The whole card as one sentence for VoiceOver.
    public let accessibilityLabel: String
}

/// Picks the shown night and compares it with the nights before.
public struct GetSleepOverview: Sendable {
    private let calendar: Calendar
    private let locale: Locale

    public init(calendar: Calendar, locale: Locale) {
        self.calendar = calendar
        self.locale = locale
    }

    public func execute(nights: [SleepNight], today: LocalDate) -> SleepCardState {
        switch SleepSelection.select(nights: nights, today: today) {
        case .noData: return .noData
        case .noRecent(let last): return .noRecent(lastWakeDate: last)
        case .shown(let night, let label): return .ready(overview(night, label: label, nights: nights))
        }
    }

    private func overview(_ night: SleepNight, label: String, nights: [SleepNight]) -> SleepOverview {
        let comparison = SleepComparison.make(shown: night, nights: nights)
        let all: [(kind: SleepOverview.Stage.Kind, name: String, minutes: Int)] = [
            (.deep, "Deep", night.deepMinutes), (.core, "Core", night.coreMinutes),
            (.rem, "REM", night.remMinutes), (.awake, "Awake", night.awakeMinutes),
        ]
        let stages = night.hasStages
            ? all.filter { $0.minutes >= 1 }.map {
                SleepOverview.Stage(kind: $0.kind, name: $0.name, minutes: $0.minutes, durationText: SleepFormat.durationText(minutes: $0.minutes))
            }
            : []
        let start = time(night.sleepStart)
        let end = time(night.wakeTime)

        var sentences = ["Sleep, \(label.prefix(1).lowercased() + label.dropFirst())."]
        sentences.append("\(SleepFormat.spokenDuration(minutes: night.asleepMinutes)) asleep, from \(start) to \(end).")
        if let comparison {
            sentences.append("\(SleepFormat.spokenDelta(comparison)).")
        }
        if !stages.isEmpty {
            let parts = stages.map { stage in
                "\(stage.kind == .awake ? "awake" : stage.name) \(SleepFormat.spokenDuration(minutes: stage.minutes))"
            }
            sentences.append(parts.joined(separator: ", ") + ".")
        }

        return SleepOverview(
            label: label,
            night: night,
            durationText: SleepFormat.durationText(minutes: night.asleepMinutes),
            windowText: "\(start) \u{2013} \(end)",
            comparison: comparison,
            deltaText: comparison.map(SleepFormat.deltaText),
            comparisonCaption: comparison.map { SleepFormat.comparisonCaption(nightsUsed: $0.nightsUsed) },
            stages: stages,
            accessibilityLabel: sentences.joined(separator: " ")
        )
    }

    /// Short time style in the device's format and the calendar's time zone.
    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
