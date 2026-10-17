import Foundation
import Domain

/// The analysis of one workout, or why there is none yet.
public enum AnalysisResult: Sendable, Equatable {
    case ready(WorkoutAnalysis)
    /// Health is locked: try again after the phone is unlocked. Nothing was stored.
    case waitingForUnlock
}

/// Returns the cached analysis, else reads the workout's detail, analyzes it,
/// saves the analysis and returns it. A source without heart rate or route still
/// yields an analysis (splits from distance, or totals only). When the detail
/// cannot be read at all, the matched run's totals stand in (not cached).
public struct AnalyzeWorkout: Sendable {
    private let source: any WorkoutDetailSource
    private let analyses: any WorkoutAnalysisRepository
    private let clock: any Clock

    public init(source: any WorkoutDetailSource, analyses: any WorkoutAnalysisRepository, clock: any Clock) {
        self.source = source
        self.analyses = analyses
        self.clock = clock
    }

    public func execute(run: CompletedRun) async throws -> AnalysisResult {
        if let cached = try? await analyses.analysis(runId: run.id), cached.schemaVersion == WorkoutAnalysis.currentSchemaVersion {
            return .ready(cached)
        }
        let series: WorkoutDetailSeries
        do {
            series = try await mappingHealthErrors { try await source.detail(runId: run.id) }
        } catch HealthDataError.locked {
            return .waitingForUnlock
        } catch {
            try Task.checkCancellation()
            return .ready(.minimal(run: run, computedAt: clock.now()))
        }
        try Task.checkCancellation()
        // The series go out of scope here; only the analysis is kept.
        let analysis = WorkoutAnalyzer.analyze(series, computedAt: clock.now())
        try? await analyses.save(analysis)
        return .ready(analysis)
    }

    /// The cached analysis only: never reads Health.
    public func cached(runId: String) async -> WorkoutAnalysis? {
        guard let cached = try? await analyses.analysis(runId: runId), cached.schemaVersion == WorkoutAnalysis.currentSchemaVersion else {
            return nil
        }
        return cached
    }
}
