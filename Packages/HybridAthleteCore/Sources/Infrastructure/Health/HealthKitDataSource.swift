import Foundation
import HealthKit
import Application
import Domain

/// Reads Apple Health through HealthKit. Read-only: it never asks for write access.
///
/// Workouts come from every app that wrote them; the source name is kept as a
/// label only, with personal names removed ("Alex's Apple Watch" becomes
/// "Apple Watch"). Health values are never logged.
public struct HealthKitDataSource: HealthDataSource, StrengthWorkoutSource {
    private let store: HKHealthStore
    private let clock: any Clock
    /// Turns local plan days into the start and end moments of a query.
    private let calendar: Calendar

    public init(clock: any Clock, calendar: Calendar) {
        self.store = HKHealthStore()
        self.clock = clock
        self.calendar = calendar
    }

    // MARK: Access

    /// Every type the app reads (`HealthReadSet`), requested together.
    private static var readTypes: Set<HKObjectType> { HealthReadSet.types }

    /// The system's answer to "would the permission sheet still appear". Without
    /// Health on the device there is nothing to ask, so that counts as requested.
    /// If the status cannot be read, asking again is the safe choice.
    public func authorizationRequestStatus() async -> HealthAuthorizationRequestStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .alreadyRequested }
        do {
            switch try await store.statusForAuthorizationRequest(toShare: [], read: Self.readTypes) {
            case .unnecessary: return .alreadyRequested
            case .shouldRequest, .unknown: return .shouldRequest
            @unknown default: return .shouldRequest
            }
        } catch {
            return .shouldRequest
        }
    }

    public func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthDataError.unavailable }
        try await translatingErrors {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
        }
    }

    // MARK: Profile

    public func readProfile() async throws -> HealthProfile {
        try await translatingErrors {
            HealthProfile(ageYears: try ageYears(), biologicalSex: try biologicalSex())
        }
    }

    /// Age only; the date of birth stays inside this adapter.
    private func ageYears() throws -> Int? {
        let calendar = Calendar(identifier: .gregorian)
        let components = try store.dateOfBirthComponents()
        guard components.year != nil, let birthDate = calendar.date(from: components) else { return nil }
        return calendar.dateComponents([.year], from: birthDate, to: clock.now()).year
    }

    private func biologicalSex() throws -> BiologicalSex? {
        switch try store.biologicalSex().biologicalSex {
        case .female: .female
        case .male: .male
        case .other: .other
        case .notSet: .notSet
        @unknown default: nil
        }
    }

    // MARK: Samples

    public func readSamples(_ kind: HealthMetricKind, since: Date?, limit: Int?) async throws -> [HealthSample] {
        let datePredicate = since.map { HKQuery.predicateForSamples(withStart: $0, end: nil, options: .strictStartDate) }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: kind.quantityType, predicate: datePredicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: limit
        )
        let samples = try await translatingErrors { try await descriptor.result(for: store) }
        return samples.map { sample in
            HealthSample(
                value: sample.quantity.doubleValue(for: kind.unit),
                unit: kind.unitLabel,
                date: sample.endDate,
                sourceName: SourceLabel.normalize(sample.sourceRevision.source.name)
            )
        }
    }

    // MARK: Workouts

    public func readWorkouts(routeCheckLimit: Int) async throws -> [WorkoutSummary] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout()],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: nil
        )
        let workouts = try await translatingErrors { try await descriptor.result(for: store) }

        var summaries: [WorkoutSummary] = []
        summaries.reserveCapacity(workouts.count)
        for (index, workout) in workouts.enumerated() {
            let hasRoute = index < routeCheckLimit ? await hasRoute(workout) : nil
            summaries.append(summary(of: workout, hasRoute: hasRoute))
        }
        return summaries
    }

    private func summary(of workout: HKWorkout, hasRoute: Bool?) -> WorkoutSummary {
        let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let distanceType = Self.distanceType(for: workout.workoutActivityType)
        let elevation = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity

        return WorkoutSummary(
            id: workout.uuid.uuidString,
            activityType: HealthKitActivityNames.activityType(workout.workoutActivityType),
            sourceName: SourceLabel.normalize(workout.sourceRevision.source.name),
            start: workout.startDate,
            end: workout.endDate,
            durationSeconds: workout.duration,
            distanceMeters: distanceType
                .flatMap { workout.statistics(for: $0)?.sumQuantity() }?
                .doubleValue(for: .meter()),
            averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: bpm),
            maxHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: bpm),
            activeEnergyKilocalories: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie()),
            elevationAscendedMeters: elevation.flatMap {
                $0.is(compatibleWith: .meter()) ? $0.doubleValue(for: .meter()) : nil
            },
            hasRoute: hasRoute
        )
    }

    /// Running workouts that start from midnight on `from` up to (not including)
    /// midnight after `to`, oldest first.
    public func runningWorkouts(from: LocalDate, to: LocalDate) async throws -> [RunSummary] {
        guard let start = from.date(in: calendar), let end = to.adding(days: 1).date(in: calendar) else { return [] }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(activityPredicate: HKQuery.predicateForWorkoutActivities(workoutActivityType: .running)),
            HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: nil
        )
        let workouts = try await translatingErrors { try await descriptor.result(for: store) }
        return workouts
            .filter { $0.workoutActivityType == .running }
            .map { workout in
                let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
                let bpm = HKUnit.count().unitDivided(by: .minute())
                return RunSummary(
                    id: workout.uuid.uuidString,
                    startDate: workout.startDate,
                    distanceMeters: workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                        .sumQuantity()?
                        .doubleValue(for: .meter()) ?? 0,
                    durationSeconds: workout.duration,
                    averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: bpm),
                    maxHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: bpm)
                )
            }
    }

    // MARK: Strength

    /// Strength, functional strength, core and HIIT workouts from every source.
    public func strengthWorkouts(from: LocalDate, to: LocalDate) async throws -> [StrengthWorkoutSummary] {
        guard let start = from.date(in: calendar), let end = to.adding(days: 1).date(in: calendar) else { return [] }
        let kinds: [HKWorkoutActivityType: StrengthWorkoutKind] = [
            .traditionalStrengthTraining: .traditionalStrength,
            .functionalStrengthTraining: .functionalStrength,
            .coreTraining: .core,
            .highIntensityIntervalTraining: .hiit,
        ]
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSCompoundPredicate(orPredicateWithSubpredicates: kinds.keys.map {
                HKQuery.predicateForWorkouts(activityPredicate: HKQuery.predicateForWorkoutActivities(workoutActivityType: $0))
            }),
            HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: nil
        )
        let workouts = try await translatingErrors { try await descriptor.result(for: store) }
        return workouts.compactMap { workout in
            kinds[workout.workoutActivityType].map {
                StrengthWorkoutSummary(id: workout.uuid.uuidString, startDate: workout.startDate, durationSeconds: workout.duration, kind: $0)
            }
        }
    }

    // MARK: Sleep

    /// Sleep samples overlapping `from...to`, oldest first. In-bed samples are
    /// passed on (the domain ignores them); unknown future values are skipped.
    public func sleepSegments(from: Date, to: Date) async throws -> [SleepSegment] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(
                type: HKCategoryType(.sleepAnalysis),
                predicate: HKQuery.predicateForSamples(withStart: from, end: to, options: [])
            )],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: nil
        )
        let samples = try await translatingErrors { try await descriptor.result(for: store) }
        return samples.compactMap { sample in
            Self.stage(sample.value).map { stage in
                SleepSegment(
                    start: sample.startDate,
                    end: sample.endDate,
                    stage: stage,
                    source: SourceLabel.normalize(sample.sourceRevision.source.name)
                )
            }
        }
    }

    private static func stage(_ rawValue: Int) -> SleepStage? {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: rawValue) else { return nil }
        switch value {
        case .inBed: return .inBed
        case .awake: return .awake
        case .asleepUnspecified: return .asleepUnspecified
        case .asleepCore: return .core
        case .asleepDeep: return .deep
        case .asleepREM: return .rem
        @unknown default: return nil
        }
    }

    // MARK: Recovery

    /// HRV samples overlapping `from...to`, oldest first, in milliseconds.
    /// SDNN only. Never mix it with RMSSD.
    public func hrvSamples(from: Date, to: Date) async throws -> [HRVSample] {
        let samples = try await quantitySamples(HKQuantityType(.heartRateVariabilitySDNN), from: from, to: to)
        let milliseconds = HKUnit.secondUnit(with: .milli)
        return samples.map { sample in
            HRVSample(
                date: sample.startDate,
                valueMs: sample.quantity.doubleValue(for: milliseconds),
                source: SourceLabel.normalize(sample.sourceRevision.source.name)
            )
        }
    }

    /// Apple's daily resting heart rate estimates overlapping `from...to`,
    /// oldest first, in beats per minute.
    public func restingHeartRateSamples(from: Date, to: Date) async throws -> [RestingHRSample] {
        let samples = try await quantitySamples(HKQuantityType(.restingHeartRate), from: from, to: to)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return samples.map { sample in
            RestingHRSample(
                endDate: sample.endDate,
                bpm: sample.quantity.doubleValue(for: bpm),
                source: SourceLabel.normalize(sample.sourceRevision.source.name)
            )
        }
    }

    /// Samples of `type` overlapping `from...to`, ascending by start, no limit.
    private func quantitySamples(_ type: HKQuantityType, from: Date, to: Date) async throws(HealthDataError) -> [HKQuantitySample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: from, end: to, options: []))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: nil
        )
        return try await translatingErrors { try await descriptor.result(for: store) }
    }

    #if DEBUG
    /// DEBUG diagnostic: whether this HealthKit exposes an RMSSD HRV type at
    /// runtime (iOS 27 and later). It is never requested or read.
    public static var sdkHasRmssdType: Bool {
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            _ = HKQuantityTypeIdentifier.heartRateVariabilityRMSSD
            return true
        }
        return false
    }
    #endif

    /// Asks only whether a route object exists; route points are never loaded.
    /// A failed check reports `nil` (unknown) instead of failing the workout.
    private func hasRoute(_ workout: HKWorkout) async -> Bool? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [],
            limit: 1
        )
        do {
            return try await !descriptor.result(for: store).isEmpty
        } catch {
            return nil
        }
    }

    /// Only walking/running distance is requested, so other activities report
    /// distance as unknown for now.
    private static func distanceType(for type: HKWorkoutActivityType) -> HKQuantityType? {
        switch type {
        case .running, .walking, .hiking: HKQuantityType(.distanceWalkingRunning)
        default: nil
        }
    }

    // MARK: Errors

    /// Translates HealthKit errors into `HealthDataError` at the boundary.
    private func translatingErrors<T>(_ body: () async throws -> T) async throws(HealthDataError) -> T {
        try await translatingHealthKitErrors(body)
    }
}

private extension HealthMetricKind {
    var quantityType: HKQuantityType {
        switch self {
        case .vo2Max: HKQuantityType(.vo2Max)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        }
    }

    var unit: HKUnit {
        switch self {
        case .vo2Max:
            HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        case .restingHeartRate:
            HKUnit.count().unitDivided(by: .minute())
        }
    }
}
