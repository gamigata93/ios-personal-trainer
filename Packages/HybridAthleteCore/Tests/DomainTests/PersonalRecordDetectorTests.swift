import Foundation
import Testing
import Domain

struct PersonalRecordDetectorTests {
    private func records(_ workouts: [WorkoutSummary], now: Date = Fixture.now) -> [PersonalRecord] {
        PersonalRecordDetector.records(in: workouts, now: now)
    }

    @Test func exactlyOnTargetIsNotNormalized() throws {
        let record = try #require(records([Fixture.workout(id: "a", meters: 5_000, seconds: 1_500)]).first)
        #expect(record.distance == .fiveK)
        #expect(record.timeSeconds == 1_500)
        #expect(record.paceSecondsPerKm == 300)
        #expect(record.actualDistanceMeters == 5_000)
        #expect(record.timeIsNormalized == false)
        #expect(record.workoutId == "a")
    }

    @Test func lowerBoundaryIsIncluded() throws {
        // 4,950 m = 0.99 x 5,000. 1,485 s x 5,000 / 4,950 = 1,500 s.
        let record = try #require(records([Fixture.workout(meters: 4_950, seconds: 1_485)]).first)
        #expect(record.timeSeconds == 1_500)
        #expect(record.timeIsNormalized)
    }

    @Test func upperBoundaryIsIncluded() throws {
        // 5,150 m = 1.03 x 5,000. 1,545 s x 5,000 / 5,150 = 1,500 s.
        let record = try #require(records([Fixture.workout(meters: 5_150, seconds: 1_545)]).first)
        #expect(record.timeSeconds == 1_500)
    }

    @Test(arguments: [4_949.0, 5_151.0])
    func justOutsideEitherBoundaryIsIgnored(meters: Double) {
        #expect(records([Fixture.workout(meters: meters, seconds: 1_500)]).isEmpty)
    }

    @Test func normalizesToTargetDistance() throws {
        // 5.10 km in 25:30 (1,530 s) -> 1,530 x 5,000 / 5,100 = 1,500 s = 25:00.
        let record = try #require(records([Fixture.workout(meters: 5_100, seconds: 1_530)]).first)
        #expect(record.timeSeconds == 1_500)
        #expect(record.actualDistanceMeters == 5_100)
        #expect(record.timeIsNormalized)
    }

    @Test func fastestNormalizedTimeWins() throws {
        let slow = Fixture.workout(id: "slow", meters: 5_000, seconds: 1_500)
        let fast = Fixture.workout(id: "fast", meters: 5_100, seconds: 1_479) // 1,450 s at 5 km
        let record = try #require(records([slow, fast]).first)
        #expect(record.workoutId == "fast")
        #expect(record.timeSeconds == 1_450)
    }

    @Test func findsEachTargetSeparatelyInOrder() {
        let found = records([
            Fixture.workout(meters: 21_097.5, seconds: 6_000),
            Fixture.workout(meters: 10_000, seconds: 2_700),
            Fixture.workout(meters: 5_000, seconds: 1_300),
        ])
        #expect(found.map(\.distance) == [.fiveK, .tenK, .halfMarathon])
        #expect(found[1].paceSecondsPerKm == 270)
        #expect(found[2].targetMeters == 21_097.5)
        #expect(found[2].timeIsNormalized == false)
    }

    @Test func recordFromExactlyThirtyDaysAgoIsNew() throws {
        let record = try #require(records([Fixture.workout(daysAgo: 30, meters: 5_000)]).first)
        #expect(record.isNew)
    }

    @Test func recordOlderThanThirtyDaysIsNotNew() throws {
        let workout = Fixture.workout(daysAgo: 30 + 1 / Fixture.day, meters: 5_000) // 30 days + 1 s
        let record = try #require(records([workout]).first)
        #expect(record.isNew == false)
    }

    @Test func ignoresNonRunningWorkouts() {
        let ride = Fixture.workout(type: .cycling, meters: 5_000, seconds: 600)
        let walk = Fixture.workout(type: .walking, meters: 5_000, seconds: 3_000)
        #expect(records([ride, walk]).isEmpty)
    }

    @Test func ignoresRunsWithoutDistance() {
        #expect(records([Fixture.workout(meters: nil)]).isEmpty)
    }

    @Test func emptyInputHasNoRecords() {
        #expect(records([]).isEmpty)
    }
}
