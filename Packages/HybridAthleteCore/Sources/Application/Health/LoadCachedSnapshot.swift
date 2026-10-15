import Foundation
import Domain

/// The saved summaries, for drawing the screen before any live read finishes.
public struct LoadCachedSnapshot: Sendable {
    private let cache: any SnapshotCache

    public init(cache: any SnapshotCache) {
        self.cache = cache
    }

    public func execute() async -> CachedSnapshot? {
        await cache.load()
    }
}
