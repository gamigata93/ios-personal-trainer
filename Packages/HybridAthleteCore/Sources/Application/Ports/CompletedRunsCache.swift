import Foundation
import Domain

/// The last known completed runs for the active plan, so Home can show progress
/// at once and while the phone is locked. Implementations treat a missing,
/// corrupt or older-schema store as no cache.
public protocol CompletedRunsCache: Sendable {
    func load() async -> CachedRuns?
    func save(_ runs: CachedRuns) async throws
}

/// Summaries only: no routes, heart-rate samples or source names (a run's
/// average and max heart rate are kept).
public struct CachedRuns: Sendable, Equatable, Codable {
    /// Bump when the shape changes; older files are then ignored.
    /// 2: runs gained their average and max heart rate.
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let generatedAt: Date
    /// The plan the runs were read for. Runs cached for another plan are ignored.
    public let planId: String
    public let runs: [CompletedRun]

    public init(schemaVersion: Int = CachedRuns.currentSchemaVersion, generatedAt: Date, planId: String, runs: [CompletedRun]) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.planId = planId
        self.runs = runs
    }
}
