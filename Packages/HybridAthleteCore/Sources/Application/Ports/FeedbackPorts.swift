import Foundation
import Domain

/// The user's after-workout feedback, one per Health workout.
public protocol WorkoutFeedbackRepository: Sendable {
    /// Saves or replaces the feedback for its workout.
    func save(_ feedback: WorkoutFeedback) async throws
    func feedback(workoutId: String) async throws -> WorkoutFeedback?
    /// Feedback for workouts on `from` or later, any order.
    func feedback(since from: LocalDate) async throws -> [WorkoutFeedback]
}

/// A stored suggestion and where it stands.
public struct StoredAdjustment: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case pending, applied, dismissed, undone
    }

    public let id: Int64
    public let planId: String
    public let createdAt: Date
    public let status: Status
    public let adjustment: PlanAdjustment

    public init(id: Int64, planId: String, createdAt: Date, status: Status, adjustment: PlanAdjustment) {
        self.id = id
        self.planId = planId
        self.createdAt = createdAt
        self.status = status
        self.adjustment = adjustment
    }
}

public enum PlanAdjustmentError: Error, Sendable, Equatable {
    /// The plan's sessions in the window changed since the suggestion was made.
    case stale
    case notFound
}

/// Suggested plan changes. Applying replaces the window's sessions in one
/// transaction; undo puts the earlier ones back.
public protocol PlanAdjustmentRepository: Sendable {
    /// Saves a pending suggestion; an older pending one for the plan is dismissed.
    func savePending(planId: String, adjustment: PlanAdjustment) async throws -> StoredAdjustment
    /// The newest pending suggestion for the plan.
    func pending(planId: String) async throws -> StoredAdjustment?
    /// Throws `PlanAdjustmentError.stale` when the window no longer holds `beforeRuns` and `beforeStrength`.
    func apply(id: Int64) async throws
    func dismiss(id: Int64) async throws
    /// Throws `PlanAdjustmentError.stale` when the window no longer holds the applied sessions.
    func undo(id: Int64) async throws
}
