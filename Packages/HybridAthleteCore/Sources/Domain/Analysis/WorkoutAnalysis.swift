import Foundation

/// What code derived from one workout: totals, splits, laps and a heart-rate
/// histogram. Cached per workout; NO coordinates and NO sample timestamps.
public struct WorkoutAnalysis: Sendable, Equatable, Codable {
    public static let currentSchemaVersion = 1

    public struct DataQuality: Sendable, Equatable, Codable {
        public let hasHr: Bool
        public let hasRoute: Bool
        public let hasDistanceSeries: Bool
        public let hasCadence: Bool
        public let hasPower: Bool

        public init(hasHr: Bool, hasRoute: Bool, hasDistanceSeries: Bool, hasCadence: Bool, hasPower: Bool) {
            self.hasHr = hasHr
            self.hasRoute = hasRoute
            self.hasDistanceSeries = hasDistanceSeries
            self.hasCadence = hasCadence
            self.hasPower = hasPower
        }

        public static let none = DataQuality(hasHr: false, hasRoute: false, hasDistanceSeries: false, hasCadence: false, hasPower: false)
    }

    public struct Totals: Sendable, Equatable, Codable {
        public let distanceKm: Double
        /// Elapsed minus paused time.
        public let movingSeconds: Double
        public let elapsedSeconds: Double
        public let pauseCount: Int
        public let pausedSeconds: Double

        public init(distanceKm: Double, movingSeconds: Double, elapsedSeconds: Double, pauseCount: Int, pausedSeconds: Double) {
            self.distanceKm = distanceKm
            self.movingSeconds = movingSeconds
            self.elapsedSeconds = elapsedSeconds
            self.pauseCount = pauseCount
            self.pausedSeconds = pausedSeconds
        }

        /// Moving seconds per km; nil without distance.
        public var paceSecPerKm: Double? {
            distanceKm > 0 ? movingSeconds / distanceKm : nil
        }
    }

    /// One kilometre (or the partial last one).
    public struct Split: Sendable, Equatable, Codable {
        /// 1-based.
        public let index: Int
        public let distanceKm: Double
        public let movingSeconds: Double
        public let paceSecPerKm: Double
        public let avgHr: Double?
        public let maxHr: Double?
        public let gainM: Double?
        public let lossM: Double?
        /// Steps per minute.
        public let cadence: Double?

        public init(
            index: Int, distanceKm: Double, movingSeconds: Double, paceSecPerKm: Double,
            avgHr: Double? = nil, maxHr: Double? = nil, gainM: Double? = nil, lossM: Double? = nil, cadence: Double? = nil
        ) {
            self.index = index
            self.distanceKm = distanceKm
            self.movingSeconds = movingSeconds
            self.paceSecPerKm = paceSecPerKm
            self.avgHr = avgHr
            self.maxHr = maxHr
            self.gainM = gainM
            self.lossM = lossM
            self.cadence = cadence
        }

        public var isFull: Bool { distanceKm >= AnalysisRules.fullSplitKm }
    }

    public struct Lap: Sendable, Equatable, Codable {
        public let index: Int
        public let distanceKm: Double
        public let movingSeconds: Double
        public let paceSecPerKm: Double
        public let avgHr: Double?

        public init(index: Int, distanceKm: Double, movingSeconds: Double, paceSecPerKm: Double, avgHr: Double?) {
            self.index = index
            self.distanceKm = distanceKm
            self.movingSeconds = movingSeconds
            self.paceSecPerKm = paceSecPerKm
            self.avgHr = avgHr
        }
    }

    /// Seconds spent in one 2-bpm bin centered on `centerBpm` (an even value),
    /// so zones can be recomputed when the heart-rate profile changes.
    public struct HRBin: Sendable, Equatable, Codable {
        public let centerBpm: Int
        public let seconds: Double

        public init(centerBpm: Int, seconds: Double) {
            self.centerBpm = centerBpm
            self.seconds = seconds
        }
    }

    public struct Weather: Sendable, Equatable, Codable {
        public let temperatureCelsius: Double?
        public let humidityPercent: Double?

        public init(temperatureCelsius: Double?, humidityPercent: Double?) {
            self.temperatureCelsius = temperatureCelsius
            self.humidityPercent = humidityPercent
        }
    }

    public let schemaVersion: Int
    public let runId: String
    public let computedAt: Date
    public let dataQuality: DataQuality
    public let totals: Totals
    public let splits: [Split]
    public let laps: [Lap]
    public let hrHistogram: [HRBin]
    public let avgHr: Double?
    public let maxHr: Double?
    public let cadenceAvg: Double?
    public let powerAvg: Double?
    public let elevationGainM: Double?
    public let elevationLossM: Double?
    public let weather: Weather?
    public let effortScore: Double?
    /// "Apple Watch": where the data came from, for the footnote.
    public let sourceLabel: String?

    public init(
        schemaVersion: Int = WorkoutAnalysis.currentSchemaVersion,
        runId: String,
        computedAt: Date,
        dataQuality: DataQuality,
        totals: Totals,
        splits: [Split] = [],
        laps: [Lap] = [],
        hrHistogram: [HRBin] = [],
        avgHr: Double? = nil,
        maxHr: Double? = nil,
        cadenceAvg: Double? = nil,
        powerAvg: Double? = nil,
        elevationGainM: Double? = nil,
        elevationLossM: Double? = nil,
        weather: Weather? = nil,
        effortScore: Double? = nil,
        sourceLabel: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.runId = runId
        self.computedAt = computedAt
        self.dataQuality = dataQuality
        self.totals = totals
        self.splits = splits
        self.laps = laps
        self.hrHistogram = hrHistogram
        self.avgHr = avgHr
        self.maxHr = maxHr
        self.cadenceAvg = cadenceAvg
        self.powerAvg = powerAvg
        self.elevationGainM = elevationGainM
        self.elevationLossM = elevationLossM
        self.weather = weather
        self.effortScore = effortScore
        self.sourceLabel = sourceLabel
    }

    /// Totals only, from the matched run, when the workout detail cannot be read.
    public static func minimal(run: CompletedRun, computedAt: Date) -> WorkoutAnalysis {
        WorkoutAnalysis(
            runId: run.id,
            computedAt: computedAt,
            dataQuality: .none,
            totals: Totals(
                distanceKm: run.distanceKm, movingSeconds: run.durationSeconds, elapsedSeconds: run.durationSeconds,
                pauseCount: 0, pausedSeconds: 0
            ),
            avgHr: run.avgHr,
            maxHr: run.maxHr
        )
    }

    /// Full kilometres only (drift, split style and fade use these).
    public var fullSplits: [Split] { splits.filter(\.isFull) }
}
