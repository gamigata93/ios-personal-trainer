import Foundation

// The detail of ONE workout as read from the health store, in memory only.
// Times are seconds since the workout started. These types are never stored
// and never sent anywhere: `WorkoutAnalyzer` turns them into a `WorkoutAnalysis`.
// Coordinates never get this far: the adapter turns a route into distances and
// altitudes first.

/// Cumulative distance at a moment.
public struct DistancePoint: Sendable, Equatable {
    public let t: Double
    public let meters: Double

    public init(t: Double, meters: Double) {
        self.t = t
        self.meters = meters
    }
}

/// Where the distance timeline came from.
public enum DistanceSource: String, Sendable, Equatable, Codable {
    /// Distance samples written with the workout.
    case samples
    /// Distances between route points, scaled to the workout total.
    case route
}

/// Cumulative meters by time, ascending.
public struct DistanceTimeline: Sendable, Equatable {
    public let points: [DistancePoint]
    public let source: DistanceSource

    public init(points: [DistancePoint], source: DistanceSource) {
        self.points = points.sorted { $0.t < $1.t }
        self.source = source
    }
}

/// One instantaneous reading (heart rate in bpm, altitude in m, power in W...).
public struct TimedValue: Sendable, Equatable {
    public let t: Double
    public let value: Double

    public init(t: Double, value: Double) {
        self.t = t
        self.value = value
    }
}

/// A count over an interval (steps).
public struct TimedCount: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let count: Double

    public init(start: Double, end: Double, count: Double) {
        self.start = start
        self.end = end
        self.count = count
    }
}

/// A span of time inside the workout (a pause, a lap).
public struct TimeSpan: Sendable, Equatable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    public var duration: Double { end - start }
}

/// What the workout itself says.
public struct WorkoutMeta: Sendable, Equatable {
    /// The workout's total distance, when known.
    public let distanceMeters: Double?
    /// From start to end, pauses included.
    public let elapsedSeconds: Double
    public let start: Date
    /// "Apple Watch", "WorkOutdoors" (personal names already removed).
    public let sourceLabel: String
    /// The workout's own elevation ascended metadata.
    public let ascendedMeters: Double?
    public let temperatureCelsius: Double?
    public let humidityPercent: Double?
    /// Apple's workout effort score (1-10), or the estimated one.
    public let effortScore: Double?

    public init(
        distanceMeters: Double?,
        elapsedSeconds: Double,
        start: Date,
        sourceLabel: String,
        ascendedMeters: Double? = nil,
        temperatureCelsius: Double? = nil,
        humidityPercent: Double? = nil,
        effortScore: Double? = nil
    ) {
        self.distanceMeters = distanceMeters
        self.elapsedSeconds = elapsedSeconds
        self.start = start
        self.sourceLabel = sourceLabel
        self.ascendedMeters = ascendedMeters
        self.temperatureCelsius = temperatureCelsius
        self.humidityPercent = humidityPercent
        self.effortScore = effortScore
    }
}

/// Everything read about one workout. Every series may be empty: sources differ.
public struct WorkoutDetailSeries: Sendable, Equatable {
    public let runId: String
    public let meta: WorkoutMeta
    public let distance: DistanceTimeline?
    public let heartRate: [TimedValue]
    /// Altitude in meters, from the route.
    public let altitude: [TimedValue]
    public let steps: [TimedCount]
    public let power: [TimedValue]
    public let pauses: [TimeSpan]
    /// Lap or segment events.
    public let laps: [TimeSpan]

    public init(
        runId: String,
        meta: WorkoutMeta,
        distance: DistanceTimeline? = nil,
        heartRate: [TimedValue] = [],
        altitude: [TimedValue] = [],
        steps: [TimedCount] = [],
        power: [TimedValue] = [],
        pauses: [TimeSpan] = [],
        laps: [TimeSpan] = []
    ) {
        self.runId = runId
        self.meta = meta
        self.distance = distance
        self.heartRate = heartRate.sorted { $0.t < $1.t }
        self.altitude = altitude.sorted { $0.t < $1.t }
        self.steps = steps
        self.power = power.sorted { $0.t < $1.t }
        self.pauses = pauses.sorted { $0.start < $1.start }
        self.laps = laps.sorted { $0.start < $1.start }
    }
}
