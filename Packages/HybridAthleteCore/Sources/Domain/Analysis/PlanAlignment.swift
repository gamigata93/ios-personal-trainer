import Foundation

/// The heart-rate target of one planned block.
public enum EffortTarget: Sendable, Equatable, Codable {
    /// Zones `low`...`high`. Upper-only targets judge only the top ("up to zone 2").
    case zones(low: Int, high: Int, upperOnly: Bool)
    /// Reps and recoveries mixed: effort is not assessed.
    case mixed
}

/// A block's target from the first keyword in its segment detail
/// (case-insensitive, checked in this order). Plain data; a proposal.
public enum EffortTargetTable {
    public static let keywords: [(keyword: String, target: EffortTarget)] = [
        ("very easy", .zones(low: 1, high: 2, upperOnly: true)),
        ("easy", .zones(low: 1, high: 2, upperOnly: true)),
        ("conversational", .zones(low: 1, high: 2, upperOnly: true)),
        ("steady", .zones(low: 2, high: 3, upperOnly: true)),
        ("comfortably hard", .zones(low: 3, high: 4, upperOnly: false)),
        ("tempo", .zones(low: 3, high: 4, upperOnly: false)),
        ("hard but controlled", .zones(low: 4, high: 5, upperOnly: false)),
    ]

    /// Threshold and intervals sessions, and any detail with reps ("x 8 min",
    /// "x 800 m"), are mixed. Nil when no keyword matches.
    public static func target(detail: String, sessionType: SessionType) -> EffortTarget? {
        if sessionType == .threshold || sessionType == .intervals || mentionsReps(detail) { return .mixed }
        let text = detail.lowercased()
        return keywords.first { text.contains($0.keyword) }?.target
    }

    /// "2 x 8 min", "4 x 800 m".
    static func mentionsReps(_ detail: String) -> Bool {
        detail.lowercased().contains(/\bx\s*\d+(?:\.\d+)?\s*(?:min|s|sec|m|km)\b/)
    }
}

/// One block's effort against its target.
public enum BlockEffortCheck: String, Sendable, Equatable, Codable {
    case onTarget, slightlyHard, tooHard, slightlyEasy, tooEasy, notAssessed

    /// Upper-only: zone <= high on target, one above slightly hard, two or more too hard.
    /// Two-sided: inside on target; above as before; one below slightly easy,
    /// two or more below too easy. Mixed, no target or no zone: not assessed.
    public static func check(zone: Int?, target: EffortTarget?) -> BlockEffortCheck {
        guard let zone, case .zones(let low, let high, let upperOnly) = target else { return .notAssessed }
        if zone > high { return zone - high == 1 ? .slightlyHard : .tooHard }
        if !upperOnly, zone < low { return low - zone == 1 ? .slightlyEasy : .tooEasy }
        return .onTarget
    }

    /// "on target", "a bit hard", "too hard", "a bit easy", "too easy", "not assessed".
    public var text: String {
        switch self {
        case .onTarget: "on target"
        case .slightlyHard: "a bit hard"
        case .tooHard: "too hard"
        case .slightlyEasy: "a bit easy"
        case .tooEasy: "too easy"
        case .notAssessed: "not assessed"
        }
    }

    /// The chip: "On target", "A bit hard", ...
    public var chipText: String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Worse first: too hard, slightly hard, too easy, slightly easy, on target.
    var severity: Int {
        switch self {
        case .tooHard: 5
        case .slightlyHard: 4
        case .tooEasy: 3
        case .slightlyEasy: 2
        case .onTarget: 1
        case .notAssessed: 0
        }
    }
}

/// One planned block placed on the actual run.
public struct AlignedBlock: Sendable, Equatable {
    public let label: String
    public let detail: String
    public let plannedKm: Double
    /// Planned position, km from the start.
    public let plannedStartKm: Double
    public let plannedEndKm: Double
    /// Estimated position on the actual run.
    public let actualStartKm: Double
    public let actualEndKm: Double
    public let paceSecPerKm: Double?
    public let avgHr: Double?
    public let zone: Int?
    public let target: EffortTarget?
    public let check: BlockEffortCheck
}

/// The run compared with the planned session block by block. Block k covers
/// [cumPlanned(k-1) / totalPlanned, cumPlanned(k) / totalPlanned] of the ACTUAL
/// distance (estimated boundaries); its pace and heart rate come from the splits.
public enum PlanAlignment {
    public static func align(
        session: PlannedSession, analysis: WorkoutAnalysis, profile: HeartRateProfile?
    ) -> [AlignedBlock] {
        let segments = session.segments.compactMap { segment -> (Segment, Double)? in
            guard let km = segment.distanceKm, km > 0 else { return nil }
            return (segment, km)
        }
        let totalPlanned = segments.map(\.1).reduce(0, +)
        let actual = analysis.splits.map(\.distanceKm).reduce(0, +)
        guard totalPlanned > 0, actual > 0 else { return [] }

        var cumulative = 0.0
        return segments.map { segment, km in
            let plannedStart = cumulative
            cumulative += km
            let start = plannedStart / totalPlanned * actual
            let end = cumulative / totalPlanned * actual
            let window = SplitWindow(splits: analysis.splits, from: start, to: end)
            let zone = window.avgHr.flatMap { hr in profile.map { $0.zone(for: hr) } }
            let target = EffortTargetTable.target(detail: segment.detail, sessionType: session.type)
            return AlignedBlock(
                label: segment.label,
                detail: segment.detail,
                plannedKm: km,
                plannedStartKm: plannedStart,
                plannedEndKm: cumulative,
                actualStartKm: start,
                actualEndKm: end,
                paceSecPerKm: window.pace,
                avgHr: window.avgHr,
                zone: zone,
                target: target,
                check: target == .mixed ? .notAssessed : BlockEffortCheck.check(zone: zone, target: target)
            )
        }
    }
}

/// Moving time and time-weighted heart rate over a distance range, interpolated
/// inside the splits (each split's pace and heart rate are taken as constant).
struct SplitWindow {
    let seconds: Double
    let km: Double
    let avgHr: Double?

    init(splits: [WorkoutAnalysis.Split], from: Double, to: Double) {
        var seconds = 0.0
        var km = 0.0
        var hrSum = 0.0
        var hrSeconds = 0.0
        var position = 0.0
        for split in splits {
            let start = position
            let end = position + split.distanceKm
            position = end
            let overlap = max(0, min(to, end) - max(from, start))
            guard overlap > 0, split.distanceKm > 0 else { continue }
            let part = split.movingSeconds * overlap / split.distanceKm
            seconds += part
            km += overlap
            if let hr = split.avgHr {
                hrSum += hr * part
                hrSeconds += part
            }
        }
        self.seconds = seconds
        self.km = km
        self.avgHr = hrSeconds > 0 ? hrSum / hrSeconds : nil
    }

    var pace: Double? { km > 0 ? seconds / km : nil }
}
