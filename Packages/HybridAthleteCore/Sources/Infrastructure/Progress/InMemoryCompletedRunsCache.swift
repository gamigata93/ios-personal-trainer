import Foundation
import Application
import Domain

/// Completed runs in memory only. Used for UI tests, DEBUG fakes and previews.
public actor InMemoryCompletedRunsCache: CompletedRunsCache {
    private var stored: CachedRuns?

    public init(_ stored: CachedRuns? = nil) {
        self.stored = stored
    }

    public func load() async -> CachedRuns? { stored }

    public func save(_ runs: CachedRuns) async throws {
        stored = runs
    }
}
