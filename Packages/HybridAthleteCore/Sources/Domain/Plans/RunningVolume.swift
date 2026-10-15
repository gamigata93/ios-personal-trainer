import Foundation

/// Recent running load, the only input to plan fit.
public struct RunningVolume: Sendable, Equatable, Codable {
    public let weeklyKm: Double
    public let longestRunKm: Double
    /// Total running seconds / total running km over the window; `nil` without runs.
    public let avgPaceSecPerKm: Double?

    public init(weeklyKm: Double, longestRunKm: Double, avgPaceSecPerKm: Double? = nil) {
        self.weeklyKm = weeklyKm
        self.longestRunKm = longestRunKm
        self.avgPaceSecPerKm = avgPaceSecPerKm
    }

    public static let none = RunningVolume(weeklyKm: 0, longestRunKm: 0)

    /// From every running workout that started in the last 28 days (inclusive):
    /// weekly km = total distance / 4, the longest single run, and the average pace.
    /// Runs without a distance add nothing.
    public static func measure(_ workouts: [WorkoutSummary], now: Date) -> RunningVolume {
        let days = PlanFitRules.volumeWindowDays
        let windowStart = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        let runs = workouts.filter { $0.isRun && $0.start >= windowStart && $0.start <= now }
        let kilometres = runs.map { ($0.distanceMeters ?? 0) / 1_000 }
        let totalKm = kilometres.reduce(0, +)
        // Pace only counts runs that have a distance, so their time matches their km.
        let timedSeconds = runs.filter { ($0.distanceMeters ?? 0) > 0 }.map(\.durationSeconds).reduce(0, +)
        return RunningVolume(
            weeklyKm: totalKm / (Double(days) / 7),
            longestRunKm: kilometres.max() ?? 0,
            avgPaceSecPerKm: totalKm > 0 ? timedSeconds / totalKm : nil
        )
    }
}
