#if DEBUG
import Foundation
import Application
import Domain

/// A made-up person for checking the app against different ages, sexes and
/// fitness levels. DEBUG builds only.
public struct Persona: Sendable, Equatable, Identifiable {
    public let id: String
    public let ageYears: Int
    public let sex: BiologicalSex
    public let vo2Max: Double?
    public let restingHeartRate: Double
    public let weeklyKm: Double
    public let longestKm: Double

    public static let all: [Persona] = [
        Persona(id: "beginner", ageYears: 28, sex: .female, vo2Max: nil, restingHeartRate: 68, weeklyKm: 0, longestKm: 0),
        Persona(id: "casual", ageYears: 45, sex: .male, vo2Max: 38.0, restingHeartRate: 66, weeklyKm: 12, longestKm: 6),
        Persona(id: "marathoner", ageYears: 38, sex: .female, vo2Max: 49.0, restingHeartRate: 52, weeklyKm: 55, longestKm: 28),
        Persona(id: "veteran", ageYears: 63, sex: .male, vo2Max: 31.0, restingHeartRate: 60, weeklyKm: 20, longestKm: 10),
        Persona(id: "teen", ageYears: 17, sex: .male, vo2Max: 52.0, restingHeartRate: 58, weeklyKm: 20, longestKm: 10),
        Persona(id: "unsetSex", ageYears: 34, sex: .notSet, vo2Max: 41.0, restingHeartRate: 62, weeklyKm: 15, longestKm: 8),
        Persona(id: "senior", ageYears: 84, sex: .female, vo2Max: 17.0, restingHeartRate: 70, weeklyKm: 5, longestKm: 3),
    ]

    public static func named(_ id: String) -> Persona? {
        all.first { $0.id == id }
    }
}

/// Serves a persona's data as if it came from Apple Health. Access counts as
/// already granted, so the read starts straight away.
public struct PersonaHealthDataSource: HealthDataSource {
    /// Days before now of the eight shorter runs; the long run is 7 days ago.
    private static let shortRunDaysAgo: [Double] = [2, 5, 9, 12, 16, 19, 23, 26]
    private static let longRunDaysAgo: Double = 7
    private static let secondsPerKm: Double = 360
    private static let runHeartRate: Double = 145

    private let persona: Persona
    private let clock: any Clock
    private let calendar: Calendar

    public init(persona: Persona, clock: any Clock, calendar: Calendar = .current) {
        self.persona = persona
        self.clock = clock
        self.calendar = calendar
    }

    public func authorizationRequestStatus() async -> HealthAuthorizationRequestStatus { .alreadyRequested }

    public func requestAccess() async throws {}

    public func readProfile() async throws -> HealthProfile {
        HealthProfile(ageYears: persona.ageYears, biologicalSex: persona.sex)
    }

    public func readSamples(_ kind: HealthMetricKind, since: Date?, limit: Int?) async throws -> [HealthSample] {
        let value: Double? = switch kind {
        case .vo2Max: persona.vo2Max
        case .restingHeartRate: persona.restingHeartRate
        }
        guard let value else { return [] }
        return [HealthSample(value: value, unit: kind.unitLabel, date: clock.now().addingTimeInterval(-3_600), sourceName: "Apple Watch")]
    }

    /// One run of the longest distance plus the rest of four weeks' volume
    /// (4 x weekly - longest) split evenly over eight runs. No runs at weekly 0.
    public func readWorkouts(routeCheckLimit: Int) async throws -> [WorkoutSummary] {
        guard persona.weeklyKm > 0 else { return [] }
        let now = clock.now()
        let shortKm = (4 * persona.weeklyKm - persona.longestKm) / Double(Self.shortRunDaysAgo.count)
        let runs = [(Self.longRunDaysAgo, persona.longestKm)] + Self.shortRunDaysAgo.map { ($0, shortKm) }
        return runs
            .map { daysAgo, km in run(km: km, start: now.addingTimeInterval(-daysAgo * 86_400)) }
            .sorted { $0.start > $1.start }
    }

    /// No sleep: `-fakeSleep` adds scenarios on top.
    public func sleepSegments(from: Date, to: Date) async throws -> [SleepSegment] { [] }
    public func hrvSamples(from: Date, to: Date) async throws -> [HRVSample] { [] }
    public func restingHeartRateSamples(from: Date, to: Date) async throws -> [RestingHRSample] { [] }

    public func runningWorkouts(from: LocalDate, to: LocalDate) async throws -> [RunSummary] {
        try await readWorkouts(routeCheckLimit: 0).runSummaries(from: from, to: to, calendar: calendar)
    }

    private func run(km: Double, start: Date) -> WorkoutSummary {
        let seconds = km * Self.secondsPerKm
        return WorkoutSummary(
            id: "persona-\(persona.id)-\(Int(start.timeIntervalSinceReferenceDate))",
            activityType: .running,
            sourceName: "Apple Watch",
            start: start,
            end: start.addingTimeInterval(seconds),
            durationSeconds: seconds,
            distanceMeters: km * 1_000,
            averageHeartRate: Self.runHeartRate,
            maxHeartRate: Self.runHeartRate + 20,
            activeEnergyKilocalories: km * 65,
            elevationAscendedMeters: nil,
            hasRoute: false
        )
    }
}
#endif
