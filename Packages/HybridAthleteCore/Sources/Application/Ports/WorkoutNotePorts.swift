import Foundation
import Domain

/// Reads everything useful about ONE workout from the health store. The series
/// live in memory only and are released once analyzed. Throws `HealthDataError`
/// (`.locked` while the phone is locked).
public protocol WorkoutDetailSource: Sendable {
    func detail(runId: String) async throws -> WorkoutDetailSeries
}

/// Cached analyses, one per Health workout id. Summaries only, no coordinates.
public protocol WorkoutAnalysisRepository: Sendable {
    func analysis(runId: String) async throws -> WorkoutAnalysis?
    func save(_ analysis: WorkoutAnalysis) async throws
    func delete(runId: String) async throws
}

/// Stored coach notes: one current note per session.
public protocol CoachNoteRepository: Sendable {
    func note(planId: String, sessionId: String) async throws -> SavedCoachNote?
    /// Saving replaces the session's note.
    func save(_ note: SavedCoachNote) async throws
    func notes(planId: String) async throws -> [SavedCoachNote]
    func delete(planId: String, sessionId: String) async throws
}
