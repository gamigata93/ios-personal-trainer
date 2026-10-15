import Foundation
import Application
import Domain

/// Stands in when the database cannot be opened: no plan, and every write fails,
/// so nothing is silently kept in memory and lost. The file is left untouched.
public struct UnavailablePlanRepository: PlanRepository {
    public init() {}

    public func save(_ plan: TrainingPlan) async throws { throw PlanRepositoryError.noActivePlan }
    public func loadActive() async -> TrainingPlan? { nil }
    public func hasActivePlan() async -> Bool { false }
    public func deleteActive() async throws { throw PlanRepositoryError.noActivePlan }
    public func applyEdit(planId: String, edit: PlanEdit) async throws -> EditReceipt { throw PlanRepositoryError.noActivePlan }
    public func undoEdit(planId: String, editId: Int64) async throws { throw PlanRepositoryError.cannotUndo }
    public func recentEdits(planId: String, limit: Int) async throws -> [PlanEditRecord] { [] }
}
