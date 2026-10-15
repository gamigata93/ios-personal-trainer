import Foundation
import Testing
import Domain

struct RunningVolumeTests {
    static let now = UTC.date(2026, 10, 9)

    static func run(_ month: Int, _ day: Int, km: Double, type: ActivityType = .running) -> WorkoutSummary {
        let start = UTC.date(2026, month, day)
        return WorkoutSummary(
            id: "\(month)-\(day)-\(type.rawValue)", activityType: type, sourceName: "Apple Watch",
            start: start, end: start.addingTimeInterval(3_000), durationSeconds: 3_000,
            distanceMeters: km * 1_000, averageHeartRate: nil, maxHeartRate: nil,
            activeEnergyKilocalories: nil, elevationAscendedMeters: nil, hasRoute: nil
        )
    }

    /// The real last-28-days runs from the user's export, plus one just outside.
    static let realRuns = [
        run(9, 10, km: 15.19), // 29 days before now: outside the window
        run(9, 15, km: 9.41), run(9, 17, km: 4.49), run(9, 20, km: 17.00), run(9, 23, km: 8.59),
        run(9, 29, km: 5.54), run(9, 30, km: 6.08), run(10, 3, km: 11.20), run(10, 6, km: 3.68),
        run(10, 8, km: 4.77),
    ]

    @Test func measuresTheLastTwentyEightDays() {
        // 9.41 + 4.49 + 17.00 + 8.59 + 5.54 + 6.08 + 11.20 + 3.68 + 4.77 = 70.76 km; / 4 = 17.69.
        let volume = RunningVolume.measure(Self.realRuns, now: Self.now)
        #expect(abs(volume.weeklyKm - 17.69) < 1e-9)
        #expect(volume.longestRunKm == 17.0)
    }

    @Test func ignoresNonRunningWorkouts() {
        let workouts = Self.realRuns + [Self.run(10, 7, km: 60, type: .cycling), Self.run(10, 7, km: 20, type: .walking)]
        let volume = RunningVolume.measure(workouts, now: Self.now)
        #expect(volume.longestRunKm == 17.0)
        #expect(abs(volume.weeklyKm - 17.69) < 1e-9)
    }

    @Test func noRunsIsZero() {
        #expect(RunningVolume.measure([], now: Self.now) == .none)
    }

    @Test func windowStartIsInclusive() {
        // Exactly 28 days before now (11 Sep, noon) still counts.
        let volume = RunningVolume.measure([Self.run(9, 11, km: 8)], now: Self.now)
        #expect(volume.weeklyKm == 2)
    }
}
