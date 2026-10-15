import Foundation

/// The race distances records are tracked for.
public enum RecordDistance: String, Sendable, CaseIterable, Codable {
    case fiveK = "5K"
    case tenK = "10K"
    case halfMarathon = "21K"

    public var meters: Double {
        switch self {
        case .fiveK: 5_000
        case .tenK: 10_000
        case .halfMarathon: 21_097.5
        }
    }
}

public struct PersonalRecord: Sendable, Equatable, Codable {
    public let distance: RecordDistance
    public let timeSeconds: Double
    public let actualDistanceMeters: Double
    /// True when the time was scaled from a run that was not exactly on target.
    public let timeIsNormalized: Bool
    public let date: Date
    public let workoutId: String
    public let isNew: Bool

    public init(
        distance: RecordDistance,
        timeSeconds: Double,
        actualDistanceMeters: Double,
        timeIsNormalized: Bool,
        date: Date,
        workoutId: String,
        isNew: Bool
    ) {
        self.distance = distance
        self.timeSeconds = timeSeconds
        self.actualDistanceMeters = actualDistanceMeters
        self.timeIsNormalized = timeIsNormalized
        self.date = date
        self.workoutId = workoutId
        self.isNew = isNew
    }

    public var targetMeters: Double { distance.meters }
    public var paceSecondsPerKm: Double { timeSeconds / (distance.meters / 1_000) }
}

public struct PersonalRecordsSection: Sendable, Equatable {
    public let status: ReadStatus
    public let items: [PersonalRecord]

    public init(status: ReadStatus, items: [PersonalRecord]) {
        self.status = status
        self.items = items
    }

    public static func unread(_ status: ReadStatus) -> PersonalRecordsSection {
        PersonalRecordsSection(status: status, items: [])
    }
}

/// Finds the fastest 5K, 10K and half marathon among whole running workouts.
///
/// A run counts for a target when its distance is 0.99x to 1.03x the target.
/// Its time is scaled to the target assuming a steady pace, so 5.10 km in
/// 25:30 counts as a 25:00 5K. Best efforts inside longer runs are not found.
public enum PersonalRecordDetector {
    public static let lowerRatio = 0.99
    public static let upperRatio = 1.03
    public static let newWindowDays = 30

    public static func records(in workouts: [WorkoutSummary], now: Date) -> [PersonalRecord] {
        RecordDistance.allCases.compactMap { target in
            best(for: target, in: workouts, now: now)
        }
    }

    private static func best(for target: RecordDistance, in workouts: [WorkoutSummary], now: Date) -> PersonalRecord? {
        let candidates: [PersonalRecord] = workouts.compactMap { workout in
            guard workout.isRun, let distance = workout.distanceMeters, distance > 0 else { return nil }
            // The ratio (not target * factor) keeps the boundaries exact in floating point.
            let ratio = distance / target.meters
            guard ratio >= lowerRatio, ratio <= upperRatio else { return nil }
            return PersonalRecord(
                distance: target,
                timeSeconds: workout.durationSeconds * target.meters / distance,
                actualDistanceMeters: distance,
                timeIsNormalized: distance != target.meters,
                date: workout.start,
                workoutId: workout.id,
                isNew: isWithinNewWindow(workout.start, now: now)
            )
        }
        return candidates.min { $0.timeSeconds < $1.timeSeconds }
    }

    /// Inclusive: a record set exactly 30 days ago is still new.
    private static func isWithinNewWindow(_ date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) <= TimeInterval(newWindowDays) * 86_400
    }
}
