import Foundation

public struct RunHeartRateSection: Sendable, Equatable {
    public let status: ReadStatus
    public let averageBpm: Double?
    public let workoutCount: Int
    public let windowDays: Int

    public init(status: ReadStatus, averageBpm: Double?, workoutCount: Int, windowDays: Int) {
        self.status = status
        self.averageBpm = averageBpm
        self.workoutCount = workoutCount
        self.windowDays = windowDays
    }

    public static func unread(_ status: ReadStatus) -> RunHeartRateSection {
        RunHeartRateSection(status: status, averageBpm: nil, workoutCount: 0, windowDays: RunHeartRateAverage.windowDays)
    }
}

/// Average heart rate during recent runs: the mean of each run's own average,
/// so every run counts once regardless of length.
public enum RunHeartRateAverage {
    public static let windowDays = 90

    /// Uses running workouts that started within the last 90 days (inclusive)
    /// and have heart-rate data.
    public static func section(for workouts: [WorkoutSummary], now: Date) -> RunHeartRateSection {
        let windowStart = now.addingTimeInterval(-TimeInterval(windowDays) * 86_400)
        let rates = workouts.compactMap { workout -> Double? in
            guard workout.isRun, workout.start >= windowStart else { return nil }
            return workout.averageHeartRate
        }
        let average = rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count)
        return RunHeartRateSection(
            status: rates.isEmpty ? .emptyOrNotAllowed : .ok,
            averageBpm: average,
            workoutCount: rates.count,
            windowDays: windowDays
        )
    }
}
