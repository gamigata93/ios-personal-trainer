import Foundation
import Domain

enum Fixture {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let day: TimeInterval = 86_400

    static func workout(
        id: String = UUID().uuidString,
        type: ActivityType = .running,
        daysAgo: Double = 1,
        meters: Double? = nil,
        seconds: Double = 1_800,
        heartRate: Double? = nil
    ) -> WorkoutSummary {
        let start = now.addingTimeInterval(-daysAgo * day)
        return WorkoutSummary(
            id: id,
            activityType: type,
            sourceName: "Test",
            start: start,
            end: start.addingTimeInterval(seconds),
            durationSeconds: seconds,
            distanceMeters: meters,
            averageHeartRate: heartRate,
            maxHeartRate: nil,
            activeEnergyKilocalories: nil,
            elevationAscendedMeters: nil,
            hasRoute: nil
        )
    }
}
