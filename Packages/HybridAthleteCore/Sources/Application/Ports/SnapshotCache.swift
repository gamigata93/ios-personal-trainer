import Foundation
import Domain

/// The last known summaries, saved so the next launch can show them at once.
/// Implementations treat a missing, corrupt or older-schema store as no cache.
public protocol SnapshotCache: Sendable {
    func load() async -> CachedSnapshot?
    func save(_ snapshot: CachedSnapshot) async throws
}

/// One cached section and when it was read.
public struct CachedSection<Value: Codable & Sendable & Equatable>: Sendable, Equatable, Codable {
    public let value: Value
    public let asOf: Date

    public init(value: Value, asOf: Date) {
        self.value = value
        self.asOf = asOf
    }
}

/// Summaries only: no workout list, routes, trackpoints or date of birth.
public struct CachedSnapshot: Sendable, Equatable, Codable {
    /// Bump when the shape changes; older files are then ignored.
    /// 2: running volume gained the average pace.
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    /// When anything was last saved.
    public let generatedAt: Date
    public let profile: CachedSection<ProfileSummary>?
    public let vo2Max: CachedSection<VO2MaxSummary>?
    public let restingHeartRate: CachedSection<RestingHeartRateSummary>?
    public let workouts: CachedSection<WorkoutsSummary>?

    public init(
        schemaVersion: Int = CachedSnapshot.currentSchemaVersion,
        generatedAt: Date,
        profile: CachedSection<ProfileSummary>? = nil,
        vo2Max: CachedSection<VO2MaxSummary>? = nil,
        restingHeartRate: CachedSection<RestingHeartRateSummary>? = nil,
        workouts: CachedSection<WorkoutsSummary>? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.profile = profile
        self.vo2Max = vo2Max
        self.restingHeartRate = restingHeartRate
        self.workouts = workouts
    }

    public static func empty(at date: Date) -> CachedSnapshot {
        CachedSnapshot(generatedAt: date)
    }

    func with(profile: CachedSection<ProfileSummary>, at date: Date) -> CachedSnapshot {
        CachedSnapshot(generatedAt: date, profile: profile, vo2Max: vo2Max, restingHeartRate: restingHeartRate, workouts: workouts)
    }

    func with(vo2Max: CachedSection<VO2MaxSummary>, at date: Date) -> CachedSnapshot {
        CachedSnapshot(generatedAt: date, profile: profile, vo2Max: vo2Max, restingHeartRate: restingHeartRate, workouts: workouts)
    }

    func with(restingHeartRate: CachedSection<RestingHeartRateSummary>, at date: Date) -> CachedSnapshot {
        CachedSnapshot(generatedAt: date, profile: profile, vo2Max: vo2Max, restingHeartRate: restingHeartRate, workouts: workouts)
    }

    func with(workouts: CachedSection<WorkoutsSummary>, at date: Date) -> CachedSnapshot {
        CachedSnapshot(generatedAt: date, profile: profile, vo2Max: vo2Max, restingHeartRate: restingHeartRate, workouts: workouts)
    }
}
