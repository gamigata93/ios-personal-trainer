import Foundation
import Domain

/// Read-only access to the user's health store. Implementations throw
/// `HealthDataError` and return domain types only.
public protocol HealthDataSource: Sendable {
    /// Whether the permission sheet would still be shown. Never whether access
    /// was granted: HealthKit hides that on purpose.
    func authorizationRequestStatus() async -> HealthAuthorizationRequestStatus
    /// Asks for read access to every type the app uses, in one request.
    func requestAccess() async throws
    func readProfile() async throws -> HealthProfile
    /// Samples newest first, optionally only those on or after `since`.
    func readSamples(_ kind: HealthMetricKind, since: Date?, limit: Int?) async throws -> [HealthSample]
    /// All workouts from every source, newest first. Route presence is checked
    /// only for the newest `routeCheckLimit`; the rest report `hasRoute == nil`.
    func readWorkouts(routeCheckLimit: Int) async throws -> [WorkoutSummary]
    /// Running workouts only, from every source, that start on a local day from
    /// `from` through `to` (the whole last day included), oldest first.
    func runningWorkouts(from: LocalDate, to: LocalDate) async throws -> [RunSummary]
    /// Sleep samples from every source that overlap `from...to`, oldest first.
    /// Unknown future stage values are skipped.
    func sleepSegments(from: Date, to: Date) async throws -> [SleepSegment]
    /// HRV (SDNN, milliseconds) samples from every source that overlap
    /// `from...to`, oldest first. Never RMSSD.
    func hrvSamples(from: Date, to: Date) async throws -> [HRVSample]
    /// Resting heart rate samples (beats per minute) from every source that
    /// overlap `from...to`, oldest first.
    func restingHeartRateSamples(from: Date, to: Date) async throws -> [RestingHRSample]
}
