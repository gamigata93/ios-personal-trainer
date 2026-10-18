import Foundation
import Domain

/// The runs Home shows and how fresh they are.
public struct CompletedRunsResult: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// Just read from Health.
        case fresh
        /// From the cache, before or instead of a read.
        case cache
        /// Health could not be read because the phone is locked; the runs are cached ones.
        case locked
    }

    public let runs: [CompletedRun]
    /// Strength, core and HIIT workouts on the plan's days.
    public let strength: [CompletedStrength]
    /// When the runs were read; nil when nothing was ever read.
    public let asOf: Date?
    public let source: Source

    public init(runs: [CompletedRun], strength: [CompletedStrength] = [], asOf: Date?, source: Source) {
        self.runs = runs
        self.strength = strength
        self.asOf = asOf
        self.source = source
    }

    public var isLocked: Bool { source == .locked }

    public static let none = CompletedRunsResult(runs: [], asOf: nil, source: .cache)
}

extension CompletedRunsCache {
    /// The cached runs when they belong to `plan`.
    func runs(for plan: TrainingPlan) async -> CachedRuns? {
        guard let cached = await load(), cached.planId == plan.id else { return nil }
        return cached
    }
}
