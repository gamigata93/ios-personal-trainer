import Foundation
import Domain

/// Reverts one logged edit of the active plan.
public struct UndoPlanEdit: Sendable {
    private let plans: any PlanRepository

    public init(plans: any PlanRepository) {
        self.plans = plans
    }

    public func execute(editId: Int64) async throws(PlanEditError) {
        guard let plan = await plans.loadActive() else { throw .noActivePlan }
        do {
            try await plans.undoEdit(planId: plan.id, editId: editId)
        } catch PlanRepositoryError.cannotUndo {
            throw .cannotUndo
        } catch {
            throw .saveFailed
        }
    }
}
