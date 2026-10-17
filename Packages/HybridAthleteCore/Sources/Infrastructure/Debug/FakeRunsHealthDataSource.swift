#if DEBUG
import Foundation
import Application
import Domain

/// The `-fakeRuns` launch argument: a health source whose runs follow the active
/// plan AS SEEDED: runs sit on each session's original date, so moving, swapping
/// or marking a session missed never changes them. Every session originally before
/// today gets a run at 95% of its distance, except every 5th session (the 5th,
/// 10th, ...), which gets none. Today gets none.
/// Runs carry the heart rate of their session type (`heartRate(for:high:)`).
/// Everything else comes from the wrapped source. DEBUG builds only.
public struct FakeRunsHealthDataSource: HealthDataSource {
    static let distanceShare = 0.95
    static let skipEvery = 5
    static let secondsPerKm = 360.0
    /// Fake runs start at 07:00 local time.
    static let startHour = 7

    private let base: any HealthDataSource
    private let activePlan: @Sendable () async -> TrainingPlan?
    private let clock: any Clock
    private let calendar: Calendar
    /// `-fakeHeartRateHigh`: easy runs average 153 instead of 139.
    private let highHeartRate: Bool

    public init(
        base: any HealthDataSource,
        activePlan: @escaping @Sendable () async -> TrainingPlan?,
        clock: any Clock,
        calendar: Calendar,
        highHeartRate: Bool = false
    ) {
        self.base = base
        self.activePlan = activePlan
        self.clock = clock
        self.calendar = calendar
        self.highHeartRate = highHeartRate
    }

    /// Average and max heart rate by session type: easy 139/158 (153 with
    /// `high`), long 150/165, tempo 158/172, threshold 160/170, intervals 150/175.
    public static func heartRate(for type: SessionType, high: Bool = false) -> (avg: Double, max: Double) {
        switch type {
        case .easy: (high ? 153 : 139, 158)
        case .long: (150, 165)
        case .tempo: (158, 172)
        case .threshold: (160, 170)
        case .intervals: (150, 175)
        }
    }

    public func authorizationRequestStatus() async -> HealthAuthorizationRequestStatus {
        await base.authorizationRequestStatus()
    }

    public func requestAccess() async throws {
        try await base.requestAccess()
    }

    public func readProfile() async throws -> HealthProfile {
        try await base.readProfile()
    }

    public func readSamples(_ kind: HealthMetricKind, since: Date?, limit: Int?) async throws -> [HealthSample] {
        try await base.readSamples(kind, since: since, limit: limit)
    }

    public func readWorkouts(routeCheckLimit: Int) async throws -> [WorkoutSummary] {
        try await base.readWorkouts(routeCheckLimit: routeCheckLimit)
    }

    public func sleepSegments(from: Date, to: Date) async throws -> [SleepSegment] {
        try await base.sleepSegments(from: from, to: to)
    }

    public func hrvSamples(from: Date, to: Date) async throws -> [HRVSample] {
        try await base.hrvSamples(from: from, to: to)
    }

    public func restingHeartRateSamples(from: Date, to: Date) async throws -> [RestingHRSample] {
        try await base.restingHeartRateSamples(from: from, to: to)
    }

    public func runningWorkouts(from: LocalDate, to: LocalDate) async throws -> [RunSummary] {
        guard let plan = await activePlan() else { return [] }
        return Self.runs(for: plan, today: LocalDate(date: clock.now(), calendar: calendar), calendar: calendar, highHeartRate: highHeartRate)
            .filter { run in (from...to).contains(LocalDate(date: run.startDate, calendar: calendar)) }
    }

    /// Every fake run of the active plan (for the fake workout detail).
    public func allRuns() async -> [RunSummary] {
        guard let plan = await activePlan() else { return [] }
        return Self.runs(for: plan, today: LocalDate(date: clock.now(), calendar: calendar), calendar: calendar, highHeartRate: highHeartRate)
    }

    static func runs(for plan: TrainingPlan, today: LocalDate, calendar: Calendar, highHeartRate: Bool = false) -> [RunSummary] {
        plan.sessions
            .sorted { $0.originalDate < $1.originalDate }
            .enumerated()
            .filter { index, session in session.originalDate < today && (index + 1) % skipEvery != 0 }
            .compactMap { _, session in
                guard
                    let midnight = session.originalDate.date(in: calendar),
                    let start = calendar.date(byAdding: .hour, value: startHour, to: midnight)
                else { return nil }
                let km = session.distanceKm * distanceShare
                let rates = heartRate(for: session.type, high: highHeartRate)
                return RunSummary(
                    id: "fake-\(session.id)", startDate: start, distanceMeters: km * 1_000, durationSeconds: km * secondsPerKm,
                    averageHeartRate: rates.avg, maxHeartRate: rates.max
                )
            }
    }
}
#endif
