import Foundation

/// A workout type, kept as a stable string so any source's types fit.
public struct ActivityType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let running = ActivityType(rawValue: "running")
    public static let walking = ActivityType(rawValue: "walking")
    public static let hiking = ActivityType(rawValue: "hiking")
    public static let cycling = ActivityType(rawValue: "cycling")
    public static let swimming = ActivityType(rawValue: "swimming")
    public static let traditionalStrengthTraining = ActivityType(rawValue: "traditionalStrengthTraining")
    public static let functionalStrengthTraining = ActivityType(rawValue: "functionalStrengthTraining")
    public static let highIntensityIntervalTraining = ActivityType(rawValue: "highIntensityIntervalTraining")
    public static let yoga = ActivityType(rawValue: "yoga")
    public static let rowing = ActivityType(rawValue: "rowing")
    public static let elliptical = ActivityType(rawValue: "elliptical")
    public static let crossTraining = ActivityType(rawValue: "crossTraining")
    public static let coreTraining = ActivityType(rawValue: "coreTraining")
    public static let stairClimbing = ActivityType(rawValue: "stairClimbing")
    public static let pilates = ActivityType(rawValue: "pilates")
    public static let mixedCardio = ActivityType(rawValue: "mixedCardio")
    public static let flexibility = ActivityType(rawValue: "flexibility")
    public static let cooldown = ActivityType(rawValue: "cooldown")

    public static func other(code: UInt) -> ActivityType {
        ActivityType(rawValue: "other(\(code))")
    }
}

/// One workout from any app, with whatever detail that app recorded.
/// `nil` means unknown: the source did not record it or it was not readable.
public struct WorkoutSummary: Sendable, Equatable {
    public let id: String
    public let activityType: ActivityType
    /// Which app wrote it. A label only, never a filter.
    public let sourceName: String
    public let start: Date
    public let end: Date
    public let durationSeconds: Double
    public let distanceMeters: Double?
    public let averageHeartRate: Double?
    public let maxHeartRate: Double?
    public let activeEnergyKilocalories: Double?
    public let elevationAscendedMeters: Double?
    /// Only checked for the newest workouts; `nil` when not checked.
    public let hasRoute: Bool?

    public init(
        id: String,
        activityType: ActivityType,
        sourceName: String,
        start: Date,
        end: Date,
        durationSeconds: Double,
        distanceMeters: Double?,
        averageHeartRate: Double?,
        maxHeartRate: Double?,
        activeEnergyKilocalories: Double?,
        elevationAscendedMeters: Double?,
        hasRoute: Bool?
    ) {
        self.id = id
        self.activityType = activityType
        self.sourceName = sourceName
        self.start = start
        self.end = end
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.elevationAscendedMeters = elevationAscendedMeters
        self.hasRoute = hasRoute
    }

    public var isRun: Bool { activityType == .running }
}

public struct WorkoutsSection: Sendable, Equatable {
    public static let latestCount = 10

    public let status: ReadStatus
    public let total: Int
    public let bySource: [String: Int]
    public let byActivityType: [String: Int]
    /// Every workout, newest first. Kept in memory for the dashboard's
    /// calculations; only `latest` is shown in the JSON.
    public let all: [WorkoutSummary]

    public init(status: ReadStatus, total: Int, bySource: [String: Int], byActivityType: [String: Int], all: [WorkoutSummary]) {
        self.status = status
        self.total = total
        self.bySource = bySource
        self.byActivityType = byActivityType
        self.all = all
    }

    /// The newest workouts, for display.
    public var latest: [WorkoutSummary] {
        Array(all.prefix(Self.latestCount))
    }

    public static func unread(_ status: ReadStatus) -> WorkoutsSection {
        WorkoutsSection(status: status, total: 0, bySource: [:], byActivityType: [:], all: [])
    }

    /// Counts workouts by source and type and keeps them all, newest first.
    public static func summarizing(_ workouts: [WorkoutSummary]) -> WorkoutsSection {
        WorkoutsSection(
            status: workouts.isEmpty ? .emptyOrNotAllowed : .ok,
            total: workouts.count,
            bySource: Dictionary(workouts.map { ($0.sourceName, 1) }, uniquingKeysWith: +),
            byActivityType: Dictionary(workouts.map { ($0.activityType.rawValue, 1) }, uniquingKeysWith: +),
            all: workouts.sorted { $0.start > $1.start }
        )
    }
}
