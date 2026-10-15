import Foundation
import Domain

/// The saved plan, if any.
public struct LoadActivePlan: Sendable {
    private let plans: any PlanRepository

    public init(plans: any PlanRepository) {
        self.plans = plans
    }

    public func execute() async -> TrainingPlan? {
        await plans.loadActive()
    }
}
