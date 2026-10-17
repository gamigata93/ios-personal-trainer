import Foundation
import Domain

/// One completed run worded for Session detail: result tiles, the splits chart,
/// heart-rate zones, plan vs actual and the data footnote. Sections without
/// data are empty (and hidden), never shown empty.
public struct WorkoutBreakdown: Sendable, Equatable {
    public struct Tile: Sendable, Equatable, Identifiable {
        public let id: String
        public let label: String
        public let value: String
        /// "Zone 3" under the average heart rate.
        public let detail: String?
        public let spoken: String
    }

    public struct SplitBar: Sendable, Equatable, Identifiable {
        public let index: Int
        public var id: Int { index }
        public let km: Double
        /// "1", or "6 (0.4)" for a partial split.
        public let label: String
        /// "6:30".
        public let paceText: String
        /// km/h: the bar height is proportional to speed.
        public let speed: Double
        /// "135", nil without heart rate.
        public let hrText: String?
        /// "Kilometre 2, 5 minutes 12 seconds per kilometre, heart rate 158".
        public let spoken: String
    }

    /// A planned block's place on the actual distance, for the strip under the chart.
    public struct BlockSpan: Sendable, Equatable, Identifiable {
        public let id: Int
        public let label: String
        public let startKm: Double
        public let endKm: Double
    }

    public struct ZoneRow: Sendable, Equatable, Identifiable {
        public let zone: Int
        public var id: Int { zone }
        /// "Z1".
        public let name: String
        /// "13 min".
        public let minutesText: String
        /// Share of the time with heart rate, 0...1.
        public let share: Double
        public let isTarget: Bool
        public let spoken: String
    }

    public struct BlockRow: Sendable, Equatable, Identifiable {
        public let id: Int
        public let label: String
        /// "1.0 km planned".
        public let plannedText: String
        /// "6:30 /km".
        public let paceText: String?
        /// "HR 135 bpm · Zone 2".
        public let hrText: String?
        /// "On target", "A bit hard", ..., "Not assessed".
        public let chip: String
        public let spoken: String
    }

    public let verdict: WorkoutVerdict
    public let tiles: [Tile]
    public let splits: [SplitBar]
    /// "Pace per kilometre for 5 kilometres: fastest 5:06, slowest 6:40."
    public let splitsSummary: String?
    /// The run's split distance, for the block strip.
    public let totalKm: Double
    public let blockSpans: [BlockSpan]
    /// Empty without heart rate or a profile.
    public let zones: [ZoneRow]
    public let blocks: [BlockRow]
    /// "Based on heart rate and route from Apple Watch." or "No heart rate data for this run."
    public let footnote: String

    public static let blocksFootnote = "Block boundaries are estimated from the planned distances."

    public static func make(_ review: WorkoutReview) -> WorkoutBreakdown {
        let analysis = review.analysis
        let blocks = review.blocks
        return WorkoutBreakdown(
            verdict: review.verdict,
            tiles: tiles(review),
            splits: analysis.splits.map(splitBar),
            splitsSummary: splitsSummary(analysis.splits),
            totalKm: analysis.splits.map(\.distanceKm).reduce(0, +),
            blockSpans: blocks.count > 1
                ? blocks.enumerated().map { BlockSpan(id: $0.offset, label: $0.element.label, startKm: $0.element.actualStartKm, endKm: $0.element.actualEndKm) }
                : [],
            zones: zoneRows(review),
            blocks: blocks.enumerated().map { blockRow($0.offset, $0.element) },
            footnote: footnote(analysis, hasHr: review.avgHr != nil)
        )
    }

    // MARK: Tiles

    static func tiles(_ review: WorkoutReview) -> [Tile] {
        let analysis = review.analysis
        let moving = analysis.totals.movingSeconds > 0 ? analysis.totals.movingSeconds : review.run.durationSeconds
        let distance = SessionFormat.distanceText(km: review.doneKm)
        let movingText = SessionFormat.runDurationText(seconds: moving)
        var tiles = [
            Tile(id: "distance", label: "Distance", value: distance, detail: nil, spoken: "Distance \(distance)"),
            Tile(id: "moving", label: "Moving time", value: movingText, detail: nil, spoken: "Moving time \(movingText)"),
        ]
        if let pace = review.paceSecPerKm {
            let text = WorkoutFormat.pace(pace)
            tiles.append(Tile(id: "pace", label: "Avg pace", value: text, detail: nil, spoken: "Average pace \(spokenPace(pace))"))
        }
        if let hr = review.avgHr {
            let bpm = "\(WorkoutFormat.whole(hr)) bpm"
            let zone = review.avgZone.map { "Zone \($0)" }
            tiles.append(Tile(id: "hr", label: "Avg HR", value: bpm, detail: zone, spoken: "Average heart rate \(bpm)" + (zone.map { ", \($0)" } ?? "")))
        }
        if let gain = analysis.elevationGainM {
            let text = "+\(WorkoutFormat.whole(gain)) m"
            tiles.append(Tile(id: "elevation", label: "Elevation", value: text, detail: nil, spoken: "Elevation gain \(WorkoutFormat.whole(gain)) metres"))
        }
        if let cadence = analysis.cadenceAvg {
            let text = "\(WorkoutFormat.whole(cadence)) spm"
            tiles.append(Tile(id: "cadence", label: "Cadence", value: text, detail: nil, spoken: "Cadence \(WorkoutFormat.whole(cadence)) steps per minute"))
        }
        return tiles
    }

    // MARK: Splits

    static func splitBar(_ split: WorkoutAnalysis.Split) -> SplitBar {
        let pace = WorkoutFormat.pace(split.paceSecPerKm).replacingOccurrences(of: " /km", with: "")
        let hr = split.avgHr.map { WorkoutFormat.whole($0) }
        let label = split.isFull ? "\(split.index)" : "\(split.index) (\(WorkoutFormat.oneDecimal(split.distanceKm)))"
        var spoken = "Kilometre \(split.index)"
        if !split.isFull { spoken += ", \(WorkoutFormat.oneDecimal(split.distanceKm)) kilometres" }
        spoken += ", \(spokenPace(split.paceSecPerKm))"
        if let hr { spoken += ", heart rate \(hr)" }
        return SplitBar(
            index: split.index, km: split.distanceKm, label: label, paceText: pace,
            speed: split.paceSecPerKm > 0 ? 3_600 / split.paceSecPerKm : 0, hrText: hr, spoken: spoken
        )
    }

    static func splitsSummary(_ splits: [WorkoutAnalysis.Split]) -> String? {
        let full = splits.filter(\.isFull)
        guard let fastest = full.min(by: { $0.paceSecPerKm < $1.paceSecPerKm }),
              let slowest = full.max(by: { $0.paceSecPerKm < $1.paceSecPerKm }) else { return nil }
        let pace = { (value: Double) in WorkoutFormat.pace(value).replacingOccurrences(of: " /km", with: "") }
        return "Pace per kilometre for \(splits.count) splits: fastest \(pace(fastest.paceSecPerKm)), slowest \(pace(slowest.paceSecPerKm))."
    }

    /// "5 minutes 12 seconds per kilometre".
    static func spokenPace(_ secondsPerKm: Double) -> String {
        let whole = WorkoutFormat.rounded(secondsPerKm)
        let minutes = whole / 60
        let seconds = whole % 60
        let minutesText = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        return seconds == 0
            ? "\(minutesText) per kilometre"
            : "\(minutesText) \(seconds) \(seconds == 1 ? "second" : "seconds") per kilometre"
    }

    // MARK: Zones

    static func zoneRows(_ review: WorkoutReview) -> [ZoneRow] {
        guard let seconds = review.zoneSeconds else { return [] }
        let total = seconds.reduce(0, +)
        guard total > 0 else { return [] }
        let target = targetZones(review)
        return seconds.enumerated().map { index, value in
            let zone = index + 1
            let minutes = "\(WorkoutFormat.rounded(value / 60)) min"
            let isTarget = target?.contains(zone) ?? false
            return ZoneRow(
                zone: zone, name: "Z\(zone)", minutesText: minutes, share: value / total, isTarget: isTarget,
                spoken: "Zone \(zone), \(minutes)" + (isTarget ? ", target" : "")
            )
        }
    }

    /// The main block's target: the longest planned block with zones.
    static func targetZones(_ review: WorkoutReview) -> ClosedRange<Int>? {
        let main = review.blocks.filter { if case .zones = $0.target { return true } else { return false } }
            .max { $0.plannedKm < $1.plannedKm }
        guard case .zones(let low, let high, _) = main?.target else { return nil }
        return low...high
    }

    // MARK: Blocks

    static func blockRow(_ index: Int, _ block: AlignedBlock) -> BlockRow {
        let planned = "\(SessionFormat.distanceText(km: block.plannedKm)) planned"
        let pace = block.paceSecPerKm.map(WorkoutFormat.pace)
        let hr = block.avgHr.map { "HR \(WorkoutFormat.whole($0)) bpm" + (block.zone.map { " · Zone \($0)" } ?? "") }
        let chip = block.check.chipText
        let spokenPaceText: String? = block.paceSecPerKm.map { "pace \(spokenPace($0))" }
        let parts: [String?] = [block.label, planned, spokenPaceText, hr, chip]
        let spoken = parts.compactMap { $0 }.joined(separator: ", ")
        return BlockRow(id: index, label: block.label, plannedText: planned, paceText: pace, hrText: hr, chip: chip, spoken: spoken)
    }

    // MARK: Footnote

    static func footnote(_ analysis: WorkoutAnalysis, hasHr: Bool) -> String {
        guard hasHr else { return "No heart rate data for this run." }
        let data = analysis.dataQuality.hasRoute ? "heart rate and route" : "heart rate"
        guard let source = analysis.sourceLabel, !source.isEmpty else { return "Based on \(data)." }
        return "Based on \(data) from \(source)."
    }
}

/// The Home card for the newest completed session that has a note.
public struct LatestCoachNoteCard: Sendable, Equatable {
    public let sessionId: String
    public let headline: String
    /// The note's "how it went", clamped to 2 lines in the view.
    public let summary: String
    /// "Tempo run · Mon 26 Oct".
    public let footer: String

    public static func make(plan: TrainingPlan, runs: [CompletedRun], notes: [String: SavedCoachNote], today: LocalDate) -> LatestCoachNoteCard? {
        let progress = PlanProgress(plan: plan, runs: runs, today: today)
        guard let session = plan.sessions
            .filter({ progress.matches[$0.id] != nil && notes[$0.id] != nil })
            .max(by: { $0.date < $1.date }),
            let note = notes[session.id]
        else { return nil }
        return LatestCoachNoteCard(
            sessionId: session.id,
            headline: note.note.headline,
            summary: note.note.howItWent,
            footer: "\(session.name) · \(HomeFormat.shortDate(session.date))"
        )
    }
}
