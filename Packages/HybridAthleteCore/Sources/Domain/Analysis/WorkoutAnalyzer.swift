import Foundation

/// Turns one workout's series into its analysis. Pure.
///
/// - Distance: the distance samples when present, else the route distance
///   scaled so the splits sum to the workout total.
/// - Moving time is elapsed time minus pauses; split times exclude paused time.
/// - Splits: every completed kilometre plus a partial last one; pace = moving
///   seconds / km. Heart rate is time-weighted: each sample holds until the next
///   one, for 30 s at most.
/// - Elevation: altitude smoothed with a 5-point moving average; steps of at
///   least 0.5 m count, per split, and the totals are their sums.
/// - Laps from lap or segment events when there are at least 3.
public enum WorkoutAnalyzer {
    private typealias Rules = AnalysisRules

    public static func analyze(_ series: WorkoutDetailSeries, computedAt: Date) -> WorkoutAnalysis {
        let elapsed = max(0, series.meta.elapsedSeconds)
        let pauses = mergedPauses(series.pauses, elapsed: elapsed)
        let pausedSeconds = pauses.map(\.duration).reduce(0, +)
        let clock = MovingClock(pauses: pauses)
        let timeline = usableTimeline(series)
        let heartRate = series.heartRate.filter { $0.value > 0 }
        let hr = StepSeries(samples: heartRate, end: elapsed)
        let power = StepSeries(samples: series.power.filter { $0.value > 0 }, end: elapsed)
        let elevation = ElevationSteps(altitude: series.altitude)

        let totalMeters = timeline?.total ?? max(0, series.meta.distanceMeters ?? 0)
        let movingSeconds = max(0, elapsed - pausedSeconds)
        let totals = WorkoutAnalysis.Totals(
            distanceKm: totalMeters / 1_000,
            movingSeconds: movingSeconds,
            elapsedSeconds: elapsed,
            pauseCount: pauses.count,
            pausedSeconds: pausedSeconds
        )

        let splits: [WorkoutAnalysis.Split] = timeline.map { timeline in
            splitSpans(timeline).enumerated().map { offset, span -> WorkoutAnalysis.Split in
                let moving = clock.moving(at: span.end) - clock.moving(at: span.start)
                let km = span.meters / 1_000
                let steps = series.steps.isEmpty ? nil : stepCount(series.steps, from: span.start, to: span.end)
                return WorkoutAnalysis.Split(
                    index: offset + 1,
                    distanceKm: km,
                    movingSeconds: moving,
                    paceSecPerKm: km > 0 ? moving / km : 0,
                    avgHr: hr.average(from: span.start, to: span.end),
                    maxHr: hr.max(from: span.start, to: span.end),
                    gainM: elevation.map { $0.gain(from: span.start, to: span.end) },
                    lossM: elevation.map { $0.loss(from: span.start, to: span.end) },
                    cadence: steps.flatMap { moving > 0 ? $0 / moving * 60 : nil }
                )
            }
        } ?? []

        let laps: [WorkoutAnalysis.Lap] = {
            guard let timeline, series.laps.count >= Rules.lapEventsMin else { return [] }
            return series.laps.enumerated().map { offset, lap in
                let km = max(0, timeline.meters(at: lap.end) - timeline.meters(at: lap.start)) / 1_000
                let moving = clock.moving(at: lap.end) - clock.moving(at: lap.start)
                return WorkoutAnalysis.Lap(
                    index: offset + 1,
                    distanceKm: km,
                    movingSeconds: moving,
                    paceSecPerKm: km > 0 ? moving / km : 0,
                    avgHr: hr.average(from: lap.start, to: lap.end)
                )
            }
        }()

        let totalSteps = series.steps.map(\.count).reduce(0, +)
        let meta = series.meta
        let hasWeather = meta.temperatureCelsius != nil || meta.humidityPercent != nil
        return WorkoutAnalysis(
            runId: series.runId,
            computedAt: computedAt,
            dataQuality: WorkoutAnalysis.DataQuality(
                hasHr: !heartRate.isEmpty,
                hasRoute: !series.altitude.isEmpty || series.distance?.source == .route,
                hasDistanceSeries: timeline != nil,
                hasCadence: !series.steps.isEmpty,
                hasPower: !power.isEmpty
            ),
            totals: totals,
            splits: splits,
            laps: laps,
            hrHistogram: hr.histogram(binWidth: Rules.hrBinWidth),
            avgHr: hr.average(from: 0, to: max(elapsed, heartRate.last?.t ?? 0)),
            maxHr: heartRate.map(\.value).max(),
            cadenceAvg: series.steps.isEmpty || movingSeconds <= 0 ? nil : totalSteps / movingSeconds * 60,
            powerAvg: power.average(from: 0, to: max(elapsed, series.power.last?.t ?? 0)),
            elevationGainM: elevation.map(\.totalGain) ?? meta.ascendedMeters,
            elevationLossM: elevation.map(\.totalLoss),
            weather: hasWeather ? WorkoutAnalysis.Weather(temperatureCelsius: meta.temperatureCelsius, humidityPercent: meta.humidityPercent) : nil,
            effortScore: meta.effortScore,
            sourceLabel: meta.sourceLabel
        )
    }

    // MARK: Distance

    /// Cumulative meters by time, ready to split; nil without at least two
    /// points and some distance.
    struct Timeline {
        let points: [DistancePoint]

        var total: Double { points.last?.meters ?? 0 }

        /// The first moment the distance reaches `meters` (clamped to the ends).
        func time(at meters: Double) -> Double {
            guard let first = points.first, let last = points.last else { return 0 }
            if meters <= first.meters { return first.t }
            if meters >= last.meters { return last.t }
            for (a, b) in zip(points, points.dropFirst()) where b.meters >= meters && b.meters > a.meters {
                guard a.meters < meters else { return a.t }
                let share = (meters - a.meters) / (b.meters - a.meters)
                return a.t + share * (b.t - a.t)
            }
            return last.t
        }

        /// The distance at `t` (linear between points, clamped to the ends).
        func meters(at t: Double) -> Double {
            guard let first = points.first, let last = points.last else { return 0 }
            if t <= first.t { return first.meters }
            if t >= last.t { return last.meters }
            for (a, b) in zip(points, points.dropFirst()) where b.t >= t {
                guard b.t > a.t else { return b.meters }
                return a.meters + (t - a.t) / (b.t - a.t) * (b.meters - a.meters)
            }
            return last.meters
        }
    }

    private static func usableTimeline(_ series: WorkoutDetailSeries) -> Timeline? {
        guard let distance = series.distance, distance.points.count >= 2 else { return nil }
        // Running maximum, so a stray dip never makes the distance go backwards.
        var running = 0.0
        var points = distance.points.map { point -> DistancePoint in
            running = max(running, point.meters)
            return DistancePoint(t: point.t, meters: running)
        }
        guard running > 0 else { return nil }
        if distance.source == .route, let total = series.meta.distanceMeters, total > 0 {
            let scale = total / running
            points = points.map { DistancePoint(t: $0.t, meters: $0.meters * scale) }
        }
        return Timeline(points: points)
    }

    private struct SplitSpan {
        let start: Double
        let end: Double
        let meters: Double
    }

    /// Full kilometres, then the partial rest when it is long enough.
    private static func splitSpans(_ timeline: Timeline) -> [SplitSpan] {
        let total = timeline.total
        let full = Int((total / 1_000 + 1e-9).rounded(.down))
        var spans = (0..<full).map { k in
            SplitSpan(
                start: timeline.time(at: Double(k) * 1_000),
                end: timeline.time(at: Double(k + 1) * 1_000),
                meters: 1_000
            )
        }
        let rest = total - Double(full) * 1_000
        if rest / 1_000 >= Rules.minPartialSplitKm {
            spans.append(SplitSpan(start: timeline.time(at: Double(full) * 1_000), end: timeline.points.last?.t ?? 0, meters: rest))
        }
        return spans
    }

    // MARK: Pauses

    /// Pauses clipped to the workout and merged where they overlap.
    private static func mergedPauses(_ pauses: [TimeSpan], elapsed: Double) -> [TimeSpan] {
        var merged: [TimeSpan] = []
        for pause in pauses.sorted(by: { $0.start < $1.start }) {
            let clipped = TimeSpan(start: max(0, pause.start), end: min(elapsed, pause.end))
            guard clipped.duration > 0 else { continue }
            if let last = merged.last, clipped.start <= last.end {
                merged[merged.count - 1] = TimeSpan(start: last.start, end: max(last.end, clipped.end))
            } else {
                merged.append(clipped)
            }
        }
        return merged
    }

    /// Moving seconds since the start: elapsed minus the pauses before `t`.
    struct MovingClock {
        let pauses: [TimeSpan]

        func moving(at t: Double) -> Double {
            let paused = pauses.map { max(0, min(t, $0.end) - $0.start) }.reduce(0, +)
            return max(0, t - paused)
        }
    }

    // MARK: Steps

    /// Steps inside `from...to`, each count prorated by its overlap.
    private static func stepCount(_ steps: [TimedCount], from: Double, to: Double) -> Double {
        steps.map { step in
            let length = step.end - step.start
            guard length > 0 else { return (step.start >= from && step.start < to) ? step.count : 0 }
            let overlap = max(0, min(to, step.end) - max(from, step.start))
            return step.count * overlap / length
        }.reduce(0, +)
    }
}

/// Instantaneous samples as a step function: each value holds from its time to
/// the next sample's, for 30 s at most (and never past `end`).
struct StepSeries {
    let samples: [TimedValue]
    let end: Double

    var isEmpty: Bool { samples.isEmpty }

    /// (value, from, to) pieces.
    private var pieces: [(value: Double, from: Double, to: Double)] {
        samples.enumerated().map { index, sample in
            let next = index + 1 < samples.count ? samples[index + 1].t : Swift.max(end, sample.t)
            let to = Swift.min(next, sample.t + AnalysisRules.hrSampleGapCapSeconds)
            return (sample.value, sample.t, Swift.max(sample.t, to))
        }
    }

    /// The time-weighted average inside `from...to`; nil without coverage.
    func average(from: Double, to: Double) -> Double? {
        var sum = 0.0
        var seconds = 0.0
        for piece in pieces {
            let overlap = Swift.max(0, Swift.min(to, piece.to) - Swift.max(from, piece.from))
            sum += piece.value * overlap
            seconds += overlap
        }
        return seconds > 0 ? sum / seconds : nil
    }

    /// The highest sample inside `from..<to`.
    func max(from: Double, to: Double) -> Double? {
        samples.filter { $0.t >= from && $0.t < to }.map(\.value).max()
    }

    /// Seconds per 2-bpm bin centered on even values (138 holds 137...138.99).
    func histogram(binWidth: Int) -> [WorkoutAnalysis.HRBin] {
        var bins: [Int: Double] = [:]
        for piece in pieces where piece.to > piece.from {
            let center = AnalysisMath.rounded(piece.value / Double(binWidth)) * binWidth
            bins[center, default: 0] += piece.to - piece.from
        }
        return bins.keys.sorted().map { WorkoutAnalysis.HRBin(centerBpm: $0, seconds: bins[$0] ?? 0) }
    }
}

/// Climbs and descents from smoothed altitude: a 5-point moving average, and
/// only steps of at least 0.5 m count. Each step is placed at the time it was counted.
struct ElevationSteps {
    private let steps: [(t: Double, delta: Double)]

    init?(altitude: [TimedValue]) {
        guard altitude.count >= 2 else { return nil }
        let window = AnalysisRules.altitudeSmoothingPoints
        let half = window / 2
        let smoothed = altitude.indices.map { index -> TimedValue in
            let lower = Swift.max(0, index - half)
            let upper = Swift.min(altitude.count - 1, index + half)
            let values = altitude[lower...upper].map(\.value)
            return TimedValue(t: altitude[index].t, value: values.reduce(0, +) / Double(values.count))
        }
        var reference = smoothed[0].value
        var steps: [(t: Double, delta: Double)] = []
        for point in smoothed.dropFirst() {
            let delta = point.value - reference
            if abs(delta) >= AnalysisRules.altitudeMinStepMeters {
                steps.append((point.t, delta))
                reference = point.value
            }
        }
        self.steps = steps
    }

    var totalGain: Double { steps.filter { $0.delta > 0 }.map(\.delta).reduce(0, +) }
    var totalLoss: Double { steps.filter { $0.delta < 0 }.map { -$0.delta }.reduce(0, +) }

    func gain(from: Double, to: Double) -> Double {
        steps.filter { $0.delta > 0 && $0.t > from && $0.t <= to }.map(\.delta).reduce(0, +)
    }

    func loss(from: Double, to: Double) -> Double {
        steps.filter { $0.delta < 0 && $0.t > from && $0.t <= to }.map { -$0.delta }.reduce(0, +)
    }
}
