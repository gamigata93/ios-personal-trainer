import Foundation
import Domain

/// The last known nightly summaries, so Home can show sleep at once and while
/// the phone is locked. Implementations treat a missing, corrupt or
/// older-schema store as no cache.
public protocol SleepCache: Sendable {
    func load() async -> CachedSleep?
    func save(_ sleep: CachedSleep) async throws
}

/// Nightly summaries only: never raw segments.
public struct CachedSleep: Sendable, Equatable, Codable {
    /// Bump when the shape changes; older files are then ignored.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    /// Oldest first.
    public let nights: [SleepNight]

    public init(schemaVersion: Int = CachedSleep.currentSchemaVersion, generatedAt: Date, nights: [SleepNight]) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.nights = nights
    }
}
