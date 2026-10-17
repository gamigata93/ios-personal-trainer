import Foundation
import CoreLocation
import HealthKit
import Application
import Domain

/// Reads everything useful about ONE workout: its heart rate, distance, step and
/// running power samples, its route (turned into distances and altitudes right
/// here: coordinates never leave this type), its pause, resume, lap and segment
/// events, weather metadata and Apple's effort score. The only code that touches
/// these samples and the route. Times become seconds since the workout start.
/// Values are never logged, and nothing is kept after the call returns.
public struct HealthKitWorkoutDetailSource: WorkoutDetailSource {
    private let store: HKHealthStore

    public init() {
        store = HKHealthStore()
    }

    public func detail(runId: String) async throws -> WorkoutDetailSeries {
        guard let uuid = UUID(uuidString: runId) else { throw HealthDataError.failed }
        return try await translatingHealthKitErrors {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.workout(HKQuery.predicateForObject(with: uuid))],
                sortDescriptors: [],
                limit: 1
            )
            guard let workout = try await descriptor.result(for: store).first else { throw HealthDataError.failed }
            return try await series(for: workout, runId: runId)
        }
    }

    private func series(for workout: HKWorkout, runId: String) async throws -> WorkoutDetailSeries {
        let start = workout.startDate
        func t(_ date: Date) -> Double { date.timeIntervalSince(start) }
        let bpm = HKUnit.count().unitDivided(by: .minute())

        let heartRate = try await samples(.heartRate, of: workout).map { TimedValue(t: t($0.startDate), value: $0.quantity.doubleValue(for: bpm)) }
        let distanceSamples = try await samples(.distanceWalkingRunning, of: workout)
        let steps = try await samples(.stepCount, of: workout).map {
            TimedCount(start: t($0.startDate), end: t($0.endDate), count: $0.quantity.doubleValue(for: .count()))
        }
        let power = try await samples(.runningPower, of: workout).map { TimedValue(t: t($0.startDate), value: $0.quantity.doubleValue(for: .watt())) }
        let route = try await routePoints(of: workout, start: start)

        let distance: DistanceTimeline?
        if !distanceSamples.isEmpty {
            distance = Self.timeline(distanceSamples.map { (t($0.startDate), t($0.endDate), $0.quantity.doubleValue(for: .meter())) })
        } else if route.distance.count >= 2 {
            distance = DistanceTimeline(points: route.distance, source: .route)
        } else {
            distance = nil
        }

        let events = workout.workoutEvents ?? []
        let laps = events.filter { $0.type == .lap }.map { TimeSpan(start: t($0.dateInterval.start), end: t($0.dateInterval.end)) }
        let segments = events.filter { $0.type == .segment }.map { TimeSpan(start: t($0.dateInterval.start), end: t($0.dateInterval.end)) }

        return WorkoutDetailSeries(
            runId: runId,
            meta: WorkoutMeta(
                distanceMeters: workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()),
                elapsedSeconds: workout.endDate.timeIntervalSince(start),
                start: start,
                sourceLabel: SourceLabel.normalize(workout.sourceRevision.source.name),
                ascendedMeters: (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity).flatMap {
                    $0.is(compatibleWith: .meter()) ? $0.doubleValue(for: .meter()) : nil
                },
                temperatureCelsius: (workout.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity).flatMap {
                    $0.is(compatibleWith: .degreeCelsius()) ? $0.doubleValue(for: .degreeCelsius()) : nil
                },
                humidityPercent: (workout.metadata?[HKMetadataKeyWeatherHumidity] as? HKQuantity).flatMap {
                    $0.is(compatibleWith: .percent()) ? $0.doubleValue(for: .percent()) * 100 : nil
                },
                effortScore: await effortScore(of: workout)
            ),
            distance: distance,
            heartRate: heartRate,
            altitude: route.altitude,
            steps: steps,
            power: power,
            pauses: Self.pauses(events, start: start, end: workout.endDate),
            laps: laps.count >= AnalysisRules.lapEventsMin ? laps : segments
        )
    }

    /// Quantity samples tied to the workout, oldest first.
    private func samples(_ identifier: HKQuantityTypeIdentifier, of workout: HKWorkout) async throws -> [HKQuantitySample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: nil
        )
        return try await descriptor.result(for: store)
    }

    /// Cumulative route distance and altitude by time. Coordinates are used for
    /// the distance between neighbours and then dropped.
    private func routePoints(of workout: HKWorkout, start: Date) async throws -> (distance: [DistancePoint], altitude: [TimedValue]) {
        let routes = try await HKSampleQueryDescriptor(
            predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: nil
        ).result(for: store)
        var distance: [DistancePoint] = []
        var altitude: [TimedValue] = []
        var previous: CLLocation?
        var meters = 0.0
        for route in routes {
            for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
                let t = location.timestamp.timeIntervalSince(start)
                if let previous { meters += location.distance(from: previous) }
                previous = location
                distance.append(DistancePoint(t: t, meters: meters))
                if location.verticalAccuracy >= 0 { altitude.append(TimedValue(t: t, value: location.altitude)) }
            }
        }
        return (distance, altitude)
    }

    /// Apple's effort score for the workout, else the estimated one; nil when neither exists.
    private func effortScore(of workout: HKWorkout) async -> Double? {
        for identifier in [HKQuantityTypeIdentifier.workoutEffortScore, .estimatedWorkoutEffortScore] {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(
                    type: HKQuantityType(identifier),
                    predicate: HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil)
                )],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                limit: 1
            )
            if let sample = try? await descriptor.result(for: store).first {
                return sample.quantity.doubleValue(for: .appleEffortScore())
            }
        }
        return nil
    }

    /// Distance samples as a cumulative timeline: flat across gaps, rising inside each sample.
    static func timeline(_ samples: [(start: Double, end: Double, meters: Double)]) -> DistanceTimeline {
        var points: [DistancePoint] = []
        var cumulative = 0.0
        for sample in samples.sorted(by: { $0.start < $1.start }) {
            if points.last.map({ sample.start > $0.t }) ?? true {
                points.append(DistancePoint(t: sample.start, meters: cumulative))
            }
            cumulative += sample.meters
            points.append(DistancePoint(t: max(sample.end, sample.start), meters: cumulative))
        }
        return DistanceTimeline(points: points, source: .samples)
    }

    /// Pause (or motion pause) to the next resume; an open pause runs to the end.
    static func pauses(_ events: [HKWorkoutEvent], start: Date, end: Date) -> [TimeSpan] {
        var spans: [TimeSpan] = []
        var pausedAt: Date?
        for event in events.sorted(by: { $0.dateInterval.start < $1.dateInterval.start }) {
            switch event.type {
            case .pause, .motionPaused:
                if pausedAt == nil { pausedAt = event.dateInterval.start }
            case .resume, .motionResumed:
                if let from = pausedAt {
                    spans.append(TimeSpan(start: from.timeIntervalSince(start), end: event.dateInterval.start.timeIntervalSince(start)))
                    pausedAt = nil
                }
            default:
                break
            }
        }
        if let from = pausedAt {
            spans.append(TimeSpan(start: from.timeIntervalSince(start), end: end.timeIntervalSince(start)))
        }
        return spans
    }
}
