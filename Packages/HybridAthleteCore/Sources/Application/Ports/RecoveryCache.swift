import Foundation
import Domain

/// The last known HRV and resting heart rate summaries, so Home can show them
/// at once and while the phone is locked. Implementations treat a missing,
/// corrupt or older-schema store as no cache.
public protocol RecoveryCache: Sendable {
    func load() async -> CachedRecovery?
    func save(_ recovery: CachedRecovery) async throws
}

/// Nightly HRV and daily resting heart rate summaries only: never raw samples.
public struct CachedRecovery: Sendable, Equatable, Codable {
    /// Bump when the shape changes; older files are then ignored.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    /// Oldest first.
    public let hrv: [HRVNight]
    /// Oldest first.
    public let restingHr: [RestingHRDay]

    public init(
        schemaVersion: Int = CachedRecovery.currentSchemaVersion,
        generatedAt: Date,
        hrv: [HRVNight],
        restingHr: [RestingHRDay]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.hrv = hrv
        self.restingHr = restingHr
    }
}
