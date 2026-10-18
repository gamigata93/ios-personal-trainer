import Foundation
import Domain

/// The cached runs for a plan, shown before Health is read.
public struct LoadCompletedRuns: Sendable {
    private let cache: any CompletedRunsCache

    public init(cache: any CompletedRunsCache) {
        self.cache = cache
    }

    public func execute(for plan: TrainingPlan) async -> CompletedRunsResult {
        guard let cached = await cache.runs(for: plan) else { return .none }
        return CompletedRunsResult(runs: cached.runs, strength: cached.strength, asOf: cached.generatedAt, source: .cache)
    }
}
