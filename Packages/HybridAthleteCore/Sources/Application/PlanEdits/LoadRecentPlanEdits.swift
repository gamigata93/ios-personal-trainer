import Foundation
import Domain

/// The newest entries of the active plan's edit log (for the DEBUG plan JSON;
/// a history screen comes later).
public struct LoadRecentPlanEdits: Sendable {
    private let plans: any PlanRepository

    public init(plans: any PlanRepository) {
        self.plans = plans
    }

    public func execute(planId: String, limit: Int = 50) async -> [PlanEditRecord] {
        (try? await plans.recentEdits(planId: planId, limit: limit)) ?? []
    }
}
