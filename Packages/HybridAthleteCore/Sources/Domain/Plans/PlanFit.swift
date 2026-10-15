import Foundation

public enum FitLabel: String, Sendable, Equatable {
    case bestFit
    case greatFit
    case stretch
    case later
}

public struct PlanFitResult: Sendable, Equatable {
    public let plan: PlanKind
    public let readiness: Double
    public let label: FitLabel
    public let reason: String

    public init(plan: PlanKind, readiness: Double, label: FitLabel, reason: String) {
        self.plan = plan
        self.readiness = readiness
        self.label = label
        self.reason = reason
    }
}

/// Labels each plan from recent running volume only. VO2 max and personal
/// records never influence the result.
public enum PlanFit {
    public static let startHereReason = "Start here and build your base."

    /// Readiness = min(weekly km / required weekly km, longest run / required long run).
    public static func readiness(_ volume: RunningVolume, for plan: PlanKind) -> Double {
        let requirement = PlanFitRules.requirement(for: plan)
        return min(volume.weeklyKm / requirement.minWeeklyKm, volume.longestRunKm / requirement.minLongestKm)
    }

    /// One result per plan, smallest first. The largest plan with readiness of at
    /// least 1.0 is Best fit and smaller ready plans are Great fit; 0.7 to 1.0 is
    /// Stretch and below that Later. When nothing is ready, the smallest plan is
    /// Best fit as a starting point and the rest are Later.
    public static func evaluate(_ volume: RunningVolume) -> [PlanFitResult] {
        let plans = PlanFitRules.plans
        let scores = plans.map { readiness(volume, for: $0) }
        let best = plans.indices.last { scores[$0] >= PlanFitRules.fitReadiness }

        return plans.indices.map { index in
            let plan = plans[index]
            let score = scores[index]
            let requirement = PlanFitRules.requirement(for: plan)

            guard let best else {
                return index == 0
                    ? PlanFitResult(plan: plan, readiness: score, label: .bestFit, reason: startHereReason)
                    : PlanFitResult(plan: plan, readiness: score, label: .later, reason: laterReason(requirement))
            }

            if index == best {
                return PlanFitResult(plan: plan, readiness: score, label: .bestFit, reason: bestReason(volume))
            }
            if score >= PlanFitRules.fitReadiness {
                return PlanFitResult(plan: plan, readiness: score, label: .greatFit, reason: "Comfortably inside your current base.")
            }
            if score >= PlanFitRules.stretchReadiness {
                return PlanFitResult(plan: plan, readiness: score, label: .stretch, reason: stretchReason(requirement, volume))
            }
            return PlanFitResult(plan: plan, readiness: score, label: .later, reason: laterReason(requirement))
        }
    }

    private static func bestReason(_ volume: RunningVolume) -> String {
        "Matches your recent running: about \(km(volume.weeklyKm)) km a week, longest run \(km(volume.longestRunKm)) km."
    }

    private static func stretchReason(_ requirement: PlanFitRules.Requirement, _ volume: RunningVolume) -> String {
        "Needs about \(km(requirement.minWeeklyKm)) km a week and a \(km(requirement.minLongestKm)) km long run. "
            + "You're at \(km(volume.weeklyKm)) and \(km(volume.longestRunKm))."
    }

    private static func laterReason(_ requirement: PlanFitRules.Requirement) -> String {
        "Build a bigger base first. Needs about \(km(requirement.minWeeklyKm)) km a week "
            + "and a \(km(requirement.minLongestKm)) km long run."
    }

    /// Whole kilometres, rounded half away from zero.
    private static func km(_ value: Double) -> Int {
        Int(value.rounded())
    }
}
