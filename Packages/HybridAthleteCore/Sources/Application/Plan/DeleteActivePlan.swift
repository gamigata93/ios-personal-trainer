import Foundation
import Domain

/// Removes the saved plan, so onboarding starts again.
public struct DeleteActivePlan: Sendable {
    private let plans: any PlanRepository

    public init(plans: any PlanRepository) {
        self.plans = plans
    }

    public func execute() async throws {
        try await plans.deleteActive()
    }
}
