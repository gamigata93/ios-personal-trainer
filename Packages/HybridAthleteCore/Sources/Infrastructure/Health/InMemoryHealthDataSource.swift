import Foundation
import Application
import Domain

/// Fixed sample data in memory. Used for UI tests and previews, never for real reads.
/// Access counts as granted; wrap it in `SimulatedHealthDataSource` to start unasked.
public actor InMemoryHealthDataSource: HealthDataSource {
    private let clock: any Clock
    private let calendar: Calendar

    public init(clock: any Clock, calendar: Calendar = .current) {
        self.clock = clock
        self.calendar = calendar
    }

    public func authorizationRequestStatus() async -> HealthAuthorizationRequestStatus {
        .alreadyRequested
    }

    public func requestAccess() async throws {}

    public func readProfile() async throws -> HealthProfile {
        HealthProfile(ageYears: 34, biologicalSex: .male)
    }

    public func readSamples(_ kind: HealthMetricKind, since: Date?, limit: Int?) async throws -> [HealthSample] {
        let now = clock.now()
        let values: [Double] = switch kind {
        case .vo2Max: [46.2, 45.8, 45.9, 45.1]
        case .restingHeartRate: [52, 53, 51, 54, 52]
        }
        let samples = values.enumerated().map { index, value in
            HealthSample(
                value: value,
                unit: kind.unitLabel,
                date: now.addingTimeInterval(-Double(index) * 7 * 86_400),
                sourceName: "Apple Watch"
            )
        }
        let windowed = samples.filter { sample in since.map { sample.date >= $0 } ?? true }
        return Array(windowed.prefix(limit ?? windowed.count))
    }

    public func readWorkouts(routeCheckLimit: Int) async throws -> [WorkoutSummary] {
        let now = clock.now()
        let day = 86_400.0
        let workouts = [
            Self.run(id: "sample-5k", start: now.addingTimeInterval(-3 * day), meters: 5_000, seconds: 1_472, heartRate: 162),
            Self.run(id: "sample-easy", start: now.addingTimeInterval(-5 * day), meters: 8_000, seconds: 2_910, heartRate: 148),
            Self.run(id: "sample-10k", start: now.addingTimeInterval(-40 * day), meters: 10_050, seconds: 3_115, heartRate: 158),
            WorkoutSummary(
                id: "sample-strength",
                activityType: .traditionalStrengthTraining,
                sourceName: "Workout",
                start: now.addingTimeInterval(-2 * day),
                end: now.addingTimeInterval(-2 * day + 2_700),
                durationSeconds: 2_700,
                distanceMeters: nil,
                averageHeartRate: 118,
                maxHeartRate: 151,
                activeEnergyKilocalories: 310,
                elevationAscendedMeters: nil,
                hasRoute: nil
            ),
        ]
        let newestFirst = workouts.sorted { $0.start > $1.start }
        return newestFirst.enumerated().map { index, workout in
            index < routeCheckLimit ? workout.withRoute(workout.distanceMeters != nil) : workout
        }
    }

    /// No sleep: `-fakeSleep` adds scenarios on top.
    public func sleepSegments(from: Date, to: Date) async throws -> [SleepSegment] { [] }
    public func hrvSamples(from: Date, to: Date) async throws -> [HRVSample] { [] }
    public func restingHeartRateSamples(from: Date, to: Date) async throws -> [RestingHRSample] { [] }

    public func runningWorkouts(from: LocalDate, to: LocalDate) async throws -> [RunSummary] {
        try await readWorkouts(routeCheckLimit: 0).runSummaries(from: from, to: to, calendar: calendar)
    }

    private static func run(id: String, start: Date, meters: Double, seconds: Double, heartRate: Double) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            activityType: .running,
            sourceName: "WorkOutdoors",
            start: start,
            end: start.addingTimeInterval(seconds),
            durationSeconds: seconds,
            distanceMeters: meters,
            averageHeartRate: heartRate,
            maxHeartRate: heartRate + 18,
            activeEnergyKilocalories: meters * 0.065,
            elevationAscendedMeters: 42,
            hasRoute: nil
        )
    }
}

extension [WorkoutSummary] {
    /// The running workouts starting on a local day in `from...to`, oldest first.
    func runSummaries(from: LocalDate, to: LocalDate, calendar: Calendar) -> [RunSummary] {
        filter { $0.activityType == .running }
            .filter { (from...to).contains(LocalDate(date: $0.start, calendar: calendar)) }
            .sorted { $0.start < $1.start }
            .map { RunSummary(id: $0.id, startDate: $0.start, distanceMeters: $0.distanceMeters ?? 0, durationSeconds: $0.durationSeconds) }
    }
}

private extension WorkoutSummary {
    func withRoute(_ hasRoute: Bool) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            activityType: activityType,
            sourceName: sourceName,
            start: start,
            end: end,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            activeEnergyKilocalories: activeEnergyKilocalories,
            elevationAscendedMeters: elevationAscendedMeters,
            hasRoute: hasRoute
        )
    }
}
