import Foundation
import Application

/// Keeps the cached summaries in memory only. Used for previews and DEBUG seeding.
public actor InMemorySnapshotCache: SnapshotCache {
    private var snapshot: CachedSnapshot?

    public init(snapshot: CachedSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func load() async -> CachedSnapshot? {
        snapshot
    }

    public func save(_ snapshot: CachedSnapshot) async throws {
        self.snapshot = snapshot
    }
}
