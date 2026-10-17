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
