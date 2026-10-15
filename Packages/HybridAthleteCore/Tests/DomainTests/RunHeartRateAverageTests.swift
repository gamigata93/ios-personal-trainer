import Foundation
import Testing
import Domain

struct RunHeartRateAverageTests {
    @Test func averagesRunsInsideTheWindowIncludingTheEdge() {
        let section = RunHeartRateAverage.section(for: [
            Fixture.workout(daysAgo: 90, heartRate: 150),                        // exactly 90 days: in
            Fixture.workout(daysAgo: 10, heartRate: 160),                        // in
            Fixture.workout(daysAgo: 90 + 1 / Fixture.day, heartRate: 100),     // 90 days + 1 s: out
        ], now: Fixture.now)

        #expect(section.averageBpm == 155)
        #expect(section.workoutCount == 2)
        #expect(section.windowDays == 90)
        #expect(section.status == .ok)
    }

    @Test func skipsRunsWithoutHeartRateAndOtherActivities() {
        let section = RunHeartRateAverage.section(for: [
            Fixture.workout(daysAgo: 1, heartRate: nil),
            Fixture.workout(type: .cycling, daysAgo: 1, heartRate: 120),
            Fixture.workout(daysAgo: 2, heartRate: 148),
        ], now: Fixture.now)

        #expect(section.averageBpm == 148)
        #expect(section.workoutCount == 1)
    }

    @Test func noUsableRunsIsEmpty() {
        let section = RunHeartRateAverage.section(for: [Fixture.workout(heartRate: nil)], now: Fixture.now)
        #expect(section.averageBpm == nil)
        #expect(section.workoutCount == 0)
        #expect(section.status == .emptyOrNotAllowed)
    }
}
