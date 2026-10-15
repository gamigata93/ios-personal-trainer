import Foundation
import Testing
import Application
import Domain

struct ReadHealthBaselineTests {
    private let health = FakeHealthDataSource()
    private let clock = FakeClock(FakeHealthDataSource.now)

    private var useCase: ReadHealthBaseline { ReadHealthBaseline(health: health, clock: clock) }

    private func snapshot() async throws -> HealthSnapshot {
        var last: HealthReadUpdate?
        for await update in useCase.execute() { last = update }
        guard case .finished(let snapshot) = try #require(last) else {
            Issue.record("last update was not .finished")
            throw CancellationError()
        }
        return snapshot
    }

    @Test func allSectionsOk() async throws {
        await health.set(workouts: .success([
            FakeHealthDataSource.run(id: "5k", meters: 5_000, seconds: 1_500, heartRate: 160),
        ]))

        let result = try await snapshot()

        #expect(result.profile == ProfileSection(status: .ok, ageYears: 34, biologicalSex: .female))
        #expect(result.vo2Max.status == .ok)
        #expect(result.vo2Max.latest?.value == 46)
        #expect(result.restingHeartRate.status == .ok)
        #expect(result.restingHeartRate.average30Days == 52)
        #expect(result.workouts.status == .ok)
        #expect(result.workouts.total == 1)
        #expect(result.runHeartRate.averageBpm == 160)
        #expect(result.personalRecords.status == .ok)
        #expect(result.personalRecords.items.map(\.workoutId) == ["5k"])
        #expect(result.generatedAt == FakeHealthDataSource.now)
    }

    @Test func lockedWorkoutsDoNotBlockOtherSections() async throws {
        await health.set(workouts: .failure(.locked))

        let result = try await snapshot()

        #expect(result.workouts.status == .locked)
        #expect(result.runHeartRate.status == .locked)
        #expect(result.personalRecords.status == .locked)
        #expect(result.profile.status == .ok)
        #expect(result.vo2Max.status == .ok)
        #expect(result.restingHeartRate.status == .ok)
    }

    @Test func emptyVO2MaxIsEmptyOrNotAllowed() async throws {
        await health.set(vo2Max: .success([]))
        let result = try await snapshot()
        #expect(result.vo2Max == VO2MaxSection(status: .emptyOrNotAllowed, latest: nil, recent: []))
    }

    @Test func mapsErrorsToStatuses() async throws {
        await health.set(vo2Max: .failure(.notAllowed), restingHeartRate: .failure(.failed))
        let result = try await snapshot()
        #expect(result.vo2Max.status == .emptyOrNotAllowed)
        #expect(result.restingHeartRate.status == .error)
    }

    @Test func noWorkoutsMeansEveryWorkoutSectionIsEmpty() async throws {
        let result = try await snapshot()
        #expect(result.workouts.status == .emptyOrNotAllowed)
        #expect(result.runHeartRate.status == .emptyOrNotAllowed)
        #expect(result.personalRecords.status == .emptyOrNotAllowed)
    }

    @Test func runsWithDistanceButNoRecordDistanceAreOkWithNoItems() async throws {
        await health.set(workouts: .success([FakeHealthDataSource.run(id: "8k", meters: 8_000, seconds: 2_900, heartRate: 150)]))
        let result = try await snapshot()
        #expect(result.personalRecords == PersonalRecordsSection(status: .ok, items: []))
    }

    @Test func sectionsReportIndependentlyBeforeWorkoutsFinish() async throws {
        await health.holdWorkouts()
        var iterator = useCase.execute().makeAsyncIterator()

        // Profile, VO2 max and resting HR all arrive while workouts are still held.
        var early: [HealthReadUpdate] = []
        for _ in 0..<3 {
            early.append(try #require(await iterator.next()))
        }
        #expect(early.contains { if case .profile = $0 { true } else { false } })
        #expect(early.contains { if case .vo2Max = $0 { true } else { false } })
        #expect(early.contains { if case .restingHeartRate = $0 { true } else { false } })

        await health.releaseWorkouts()
        var rest: [HealthReadUpdate] = []
        while let update = await iterator.next() { rest.append(update) }

        #expect(rest.count == 4)
        guard case .workouts = rest[0], case .finished = rest[3] else {
            Issue.record("unexpected order: \(rest)")
            return
        }
    }
}
