#if DEBUG
import Foundation
import Application
import Domain

/// `-fakeWorkoutDetail <scenario>`: canned workout detail with no HealthKit. The
/// fake owns its series. DEBUG builds only.
public enum FakeWorkoutDetailScenario: String, Sendable, CaseIterable {
    /// A 5.0 km tempo: 6:30, 5:12, 5:08, 5:06, 6:40 /km at 135, 158, 164, 166, 142 bpm, with a route.
    case tempo
    /// An 8.0 km easy run slowing from 6:00 to 6:16 /km while heart rate climbs from 132 to 150; no route.
    case easyDrift
    /// The tempo without heart rate.
    case noHr
    /// The tempo with two pauses (60 s and 35 s).
    case paused
    /// The tempo with five lap events, one per km.
    case laps
}

/// The fake profile behind every DEBUG fake: max 182, resting 49.
public enum FakeHeartRateProfile {
    public static let profile = HeartRateProfile(maxHr: 182, restingHr: 49)
}

/// Workout detail for the DEBUG fakes. With a scenario every run gets that
/// scenario's series; without one (`-fakeRuns` alone) each run gets an even
/// effort at its own distance and the heart rate of its session type.
public struct FakeWorkoutDetailSource: WorkoutDetailSource {
    /// One kilometre (or less) of a canned run.
    struct Leg {
        let km: Double
        let pace: Double
        let avgHr: Double
        let maxHr: Double
        let gain: Double
        let loss: Double
    }

    private let scenario: FakeWorkoutDetailScenario?
    private let runs: @Sendable () async -> [RunSummary]
    private let activePlan: @Sendable () async -> TrainingPlan?
    private let highHeartRate: Bool

    public init(
        scenario: FakeWorkoutDetailScenario?,
        runs: @escaping @Sendable () async -> [RunSummary],
        activePlan: @escaping @Sendable () async -> TrainingPlan?,
        highHeartRate: Bool = false
    ) {
        self.scenario = scenario
        self.runs = runs
        self.activePlan = activePlan
        self.highHeartRate = highHeartRate
    }

    public func detail(runId: String) async throws -> WorkoutDetailSeries {
        let run = await runs().first { $0.id == runId }
        let start = run?.startDate ?? Date(timeIntervalSince1970: 0)
        if let scenario { return Self.series(scenario, runId: runId, start: start) }
        guard let run else { throw HealthDataError.failed }
        let sessionId = runId.hasPrefix("fake-") ? String(runId.dropFirst("fake-".count)) : runId
        let type = await activePlan()?.session(id: sessionId)?.type ?? .easy
        let rates = FakeRunsHealthDataSource.heartRate(for: type, high: highHeartRate)
        let km = run.distanceMeters / 1_000
        let pace = km > 0 ? run.durationSeconds / km : 360
        var legs: [Leg] = []
        var left = km
        while left > 0.0001 {
            let leg = min(1, left)
            legs.append(Leg(km: leg, pace: pace, avgHr: rates.avg, maxHr: rates.max, gain: 0, loss: 0))
            left -= leg
        }
        return Self.build(legs, runId: runId, start: start, hasRoute: false, hasHr: true)
    }

    static let tempoLegs: [Leg] = [
        Leg(km: 1, pace: 390, avgHr: 135, maxHr: 148, gain: 3, loss: 2),
        Leg(km: 1, pace: 312, avgHr: 158, maxHr: 165, gain: 4, loss: 3),
        Leg(km: 1, pace: 308, avgHr: 164, maxHr: 168, gain: 2, loss: 2),
        Leg(km: 1, pace: 306, avgHr: 166, maxHr: 170, gain: 3, loss: 2),
        Leg(km: 1, pace: 400, avgHr: 142, maxHr: 156, gain: 1, loss: 3),
    ]

    static let easyDriftLegs: [Leg] = zip(
        [360.0, 361, 362, 364, 366, 369, 372, 376],
        zip([132.0, 134, 136, 138, 141, 144, 147, 150], [138.0, 140, 142, 145, 148, 151, 154, 158])
    ).map { Leg(km: 1, pace: $0, avgHr: $1.0, maxHr: $1.1, gain: 0, loss: 0) }

    static func series(_ scenario: FakeWorkoutDetailScenario, runId: String, start: Date) -> WorkoutDetailSeries {
        switch scenario {
        case .tempo: build(tempoLegs, runId: runId, start: start, hasRoute: true, hasHr: true)
        case .easyDrift: build(easyDriftLegs, runId: runId, start: start, hasRoute: false, hasHr: true)
        case .noHr: build(tempoLegs, runId: runId, start: start, hasRoute: true, hasHr: false)
        case .paused: build(tempoLegs, runId: runId, start: start, hasRoute: true, hasHr: true, pauses: [(500, 60), (1_200, 35)])
        case .laps: build(tempoLegs, runId: runId, start: start, hasRoute: true, hasHr: true, lapEvents: true)
        }
    }

    /// Distance points every 10 s, heart rate every 5 s (one sample at the leg's
    /// max balanced by one at 2 x avg - max, so the average holds), altitude rising
    /// then falling inside each leg. `pauses` are (moving second, length) pairs.
    static func build(
        _ legs: [Leg], runId: String, start: Date, hasRoute: Bool, hasHr: Bool,
        pauses pauseSpec: [(at: Double, seconds: Double)] = [], lapEvents: Bool = false
    ) -> WorkoutDetailSeries {
        var distance: [DistancePoint] = [DistancePoint(t: 0, meters: 0)]
        var heartRate: [TimedValue] = []
        var altitude: [TimedValue] = []
        var laps: [TimeSpan] = []
        var pauses: [TimeSpan] = []
        var pending = pauseSpec.sorted { $0.at < $1.at }
        var t = 0.0
        var moving = 0.0
        var meters = 0.0
        var elevation = 100.0
        for leg in legs {
            let legSeconds = leg.km * leg.pace
            let lapStart = t
            let steps = max(1, Int((legSeconds / 5).rounded(.down)))
            let step = legSeconds / Double(steps)
            let legStartMeters = meters
            let legStartElevation = elevation
            for index in 0..<steps {
                // A pause starting inside this step: time passes, distance does not.
                if let pause = pending.first, pause.at <= moving + step {
                    pauses.append(TimeSpan(start: t, end: t + pause.seconds))
                    t += pause.seconds
                    distance.append(DistancePoint(t: t, meters: meters))
                    pending.removeFirst()
                }
                if hasHr {
                    let value = index == 0 ? leg.maxHr : (index == 1 ? 2 * leg.avgHr - leg.maxHr : leg.avgHr)
                    heartRate.append(TimedValue(t: t, value: value))
                }
                t += step
                moving += step
                let share = Double(index + 1) / Double(steps)
                meters = legStartMeters + leg.km * 1_000 * share
                if index % 2 == 1 || index == steps - 1 { distance.append(DistancePoint(t: t, meters: meters)) }
                if hasRoute {
                    let climb = leg.gain + leg.loss
                    let up = climb > 0 ? leg.gain / climb : 0
                    elevation = share <= up
                        ? legStartElevation + leg.gain * (up > 0 ? share / up : 0)
                        : legStartElevation + leg.gain - leg.loss * ((share - up) / max(1 - up, 1e-9))
                    altitude.append(TimedValue(t: t, value: elevation))
                }
            }
            elevation = legStartElevation + leg.gain - leg.loss
            laps.append(TimeSpan(start: lapStart, end: t))
        }
        return WorkoutDetailSeries(
            runId: runId,
            meta: WorkoutMeta(
                distanceMeters: meters,
                elapsedSeconds: t,
                start: start,
                sourceLabel: "Apple Watch",
                temperatureCelsius: hasRoute ? 14 : nil,
                humidityPercent: hasRoute ? 70 : nil
            ),
            distance: DistanceTimeline(points: distance, source: .samples),
            heartRate: heartRate,
            altitude: altitude,
            pauses: pauses,
            laps: lapEvents ? laps : []
        )
    }
}
#endif
