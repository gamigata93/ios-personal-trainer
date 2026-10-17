import Foundation

/// Done against planned: delta = (done - planned) / planned. Within ±10% (10%
/// included) is on plan; percent is whole, half away from zero.
public enum DistanceCheck: Sendable, Equatable, Codable {
    case onPlan(deltaKm: Double)
    case short(deltaKm: Double, percent: Int)
    case long(deltaKm: Double, percent: Int)

    public static func check(plannedKm: Double, doneKm: Double) -> DistanceCheck {
        let deltaKm = doneKm - plannedKm
        guard plannedKm > 0 else { return .onPlan(deltaKm: deltaKm) }
        let share = deltaKm / plannedKm
        if abs(share) <= AssessmentRules.distanceOkBand + 1e-9 { return .onPlan(deltaKm: deltaKm) }
        let percent = AnalysisMath.rounded(abs(share) * 100)
        return share < 0 ? .short(deltaKm: deltaKm, percent: percent) : .long(deltaKm: deltaKm, percent: percent)
    }

    public var deltaKm: Double {
        switch self {
        case .onPlan(let delta), .short(let delta, _), .long(let delta, _): delta
        }
    }

    /// Off by MORE than 25%.
    public var isOff: Bool {
        switch self {
        case .onPlan: false
        case .short(_, let percent), .long(_, let percent): Double(percent) > AssessmentRules.distanceOffBand * 100
        }
    }

    public var isOnPlan: Bool {
        if case .onPlan = self { return true }
        return false
    }

    public var isShort: Bool {
        if case .short = self { return true }
        return false
    }
}

public enum WorkoutVerdict: String, Sendable, Equatable, Codable, CaseIterable {
    case onTrack, watch, offPlan

    /// "On track", "Worth watching", "Off plan".
    public var chipText: String {
        switch self {
        case .onTrack: "On track"
        case .watch: "Worth watching"
        case .offPlan: "Off plan"
        }
    }

    /// "on track", "worth watching", "off plan".
    public var lowercasedText: String { chipText.lowercased() }
}

/// What code concludes about one run. Off plan when the distance is off by more
/// than 25% or any block is too hard; worth watching when the distance is
/// outside ±10%, a block is slightly hard or too easy, or drift is high;
/// otherwise on track. Slightly easy never lowers the verdict.
public struct WorkoutAssessment: Sendable, Equatable {
    public let distance: DistanceCheck
    public let blocks: [BlockEffortCheck]
    public let drift: HeartRateDrift.Band?

    public init(distance: DistanceCheck, blocks: [BlockEffortCheck], drift: HeartRateDrift.Band? = nil) {
        self.distance = distance
        self.blocks = blocks
        self.drift = drift
    }

    /// The worst assessed block; nil when no block was assessed.
    public var effort: BlockEffortCheck? {
        blocks.filter { $0 != .notAssessed }.max { $0.severity < $1.severity }
    }

    public var isEffortHard: Bool {
        effort == .tooHard || effort == .slightlyHard
    }

    public var verdict: WorkoutVerdict {
        if distance.isOff || blocks.contains(.tooHard) { return .offPlan }
        if !distance.isOnPlan || blocks.contains(.slightlyHard) || blocks.contains(.tooEasy) || drift == .high { return .watch }
        return .onTrack
    }
}
