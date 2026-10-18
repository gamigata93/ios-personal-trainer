import Foundation
import Application
import Domain

/// Stands in when the database could not be opened: nothing is stored, every
/// write fails (the note card then offers Try again).
public struct UnavailableCoachNoteRepository: CoachNoteRepository {
    public init() {}

    public func note(planId: String, sessionId: String) async throws -> SavedCoachNote? { nil }
    public func save(_ note: SavedCoachNote) async throws { throw PlanRepositoryError.noActivePlan }
    public func notes(planId: String) async throws -> [SavedCoachNote] { [] }
    public func delete(planId: String, sessionId: String) async throws {}
}

/// Stands in when the database could not be opened: analyses are not cached.
public struct UnavailableWorkoutAnalysisRepository: WorkoutAnalysisRepository {
    public init() {}

    public func analysis(runId: String) async throws -> WorkoutAnalysis? { nil }
    public func save(_ analysis: WorkoutAnalysis) async throws {}
    public func delete(runId: String) async throws {}
}

/// Stands in when the database could not be opened: feedback is not kept, so
/// nothing is asked (every workout reads as answered).
public struct UnavailableWorkoutFeedbackRepository: WorkoutFeedbackRepository {
    public init() {}

    public func save(_ feedback: WorkoutFeedback) async throws { throw PlanRepositoryError.noActivePlan }
    public func feedback(workoutId: String) async throws -> WorkoutFeedback? { nil }
    public func feedback(since from: LocalDate) async throws -> [WorkoutFeedback] { throw PlanRepositoryError.noActivePlan }
}

/// Stands in when the database could not be opened: no suggestions.
public struct UnavailablePlanAdjustmentRepository: PlanAdjustmentRepository {
    public init() {}

    public func savePending(planId: String, adjustment: PlanAdjustment) async throws -> StoredAdjustment { throw PlanAdjustmentError.notFound }
    public func pending(planId: String) async throws -> StoredAdjustment? { nil }
    public func apply(id: Int64) async throws { throw PlanAdjustmentError.notFound }
    public func dismiss(id: Int64) async throws {}
    public func undo(id: Int64) async throws { throw PlanAdjustmentError.notFound }
}

#if DEBUG
/// Analyses in memory: previews.
public actor InMemoryWorkoutAnalysisRepository: WorkoutAnalysisRepository {
    private var stored: [String: WorkoutAnalysis] = [:]

    public init() {}

    public func analysis(runId: String) async throws -> WorkoutAnalysis? { stored[runId] }
    public func save(_ analysis: WorkoutAnalysis) async throws { stored[analysis.runId] = analysis }
    public func delete(runId: String) async throws { stored[runId] = nil }
}
#endif
