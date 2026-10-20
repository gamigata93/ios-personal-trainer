import Foundation
import Testing
import Application
import Domain

struct CreatePlanTests {
    /// FakeHealthDataSource.now is 2026-05-10 in UTC; plan start is the Monday after.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private var today: LocalDate { LocalDate(FakeHealthDataSource.now, calendar: calendar) }

    private var setup: RaceSetup {
        RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: PlanCalendar.planStart(today: today).adding(days: 55), trainingDays: [.tuesday, .sunday])
    }

    /// Returns a fixed plan, or fails, and records the request it was given.
    private actor FakeGenerator: PlanGenerator {
        let result: Result<TrainingPlan, FakeStorageError>
        private(set) var requests: [PlanRequest] = []

        init(_ result: Result<TrainingPlan, FakeStorageError>) {
            self.result = result
        }

        func generate(_ request: PlanRequest) async throws -> TrainingPlan {
            requests.append(request)
            return try result.get()
        }
    }

    /// One valid session in each of eight weeks, ending in a taper.
    private func validPlan() -> TrainingPlan {
        let start = PlanCalendar.planStart(today: today)
        let weeks = (0..<8).map { offset in
            PlanWeek(
                index: offset + 1, startDate: start.adding(days: offset * 7),
                phase: offset == 7 ? .taper : .base, targetKm: 8,
                sessions: [PlannedSession(date: start.adding(days: offset * 7 + 1), type: .easy, name: "Easy run", distanceKm: 8,
                                          estimatedMinutes: nil, effort: "Conversational", segments: [], note: nil)]
            )
        }
        return TrainingPlan(id: "", createdAt: .distantPast, generatedBy: "fake", planKind: .tenK, race: setup, planStart: start, weeks: weeks)
    }

    private func useCase(_ generator: FakeGenerator, plans: FakePlanRepository, cache: FakeSnapshotCache = FakeSnapshotCache()) -> CreatePlan {
        CreatePlan(generator: generator, plans: plans, cache: cache, clock: FakeClock(FakeHealthDataSource.now), calendar: calendar, makeID: { "plan-1" })
    }

    @Test func outOfScopeDistancesSaveNothing() async throws {
        for km in [4.99, 50] {
            let plans = FakePlanRepository()
            let generator = FakeGenerator(.success(validPlan()))
            let race = RaceSetup(distanceKm: km, elevationGainM: 0, raceDate: setup.raceDate, trainingDays: setup.trainingDays)
            await #expect(throws: PlanCreationError.raceOutOfScope(distanceKm: km)) {
                try await useCase(generator, plans: plans).execute(race, source: .custom)
            }
            #expect(await plans.saveCount == 0)
            #expect(await generator.requests.isEmpty)
        }
    }

    @Test func aWidenedScopeAcceptsFiftyKilometres() async throws {
        let plans = FakePlanRepository()
        let race = RaceSetup(distanceKm: 50, elevationGainM: 0, raceDate: setup.raceDate, trainingDays: setup.trainingDays)
        let useCase = CreatePlan(
            generator: FakeGenerator(.success(validPlan())), plans: plans, cache: FakeSnapshotCache(), clock: FakeClock(FakeHealthDataSource.now),
            calendar: calendar, makeID: { "plan-1" }, scope: .unrestricted
        )
        _ = try await useCase.execute(race, source: .custom)
        #expect(await plans.saveCount == 1)
    }

    @Test func successSavesOnceWithInjectedIdAndDate() async throws {
        let plans = FakePlanRepository()
        let plan = try await useCase(FakeGenerator(.success(validPlan())), plans: plans).execute(setup, source: .custom)

        #expect(plan.id == "plan-1")
        #expect(plan.createdAt == FakeHealthDataSource.now)
        #expect(await plans.saveCount == 1)
        #expect(await plans.plan == plan)
    }

    @Test func passesTheCachedFitnessToTheGenerator() async throws {
        let generator = FakeGenerator(.success(validPlan()))
        let cache = FakeSnapshotCache(stored: CachedSnapshot(
            generatedAt: FakeHealthDataSource.now,
            profile: CachedSection(value: ProfileSummary(ageYears: 32, biologicalSex: .male), asOf: FakeHealthDataSource.now),
            workouts: CachedSection(
                value: WorkoutsSummary(totalCount: 9, runCount: 9, runHeartRateAverage: 140, personalRecords: [],
                                       volume: RunningVolume(weeklyKm: 17.69, longestRunKm: 17, avgPaceSecPerKm: 364)),
                asOf: FakeHealthDataSource.now
            )
        ))
        _ = try await useCase(generator, plans: FakePlanRepository(), cache: cache).execute(setup, source: .suggested(.tenK))

        let request = try #require(await generator.requests.first)
        #expect(request.fitness == FitnessSummary(weeklyKm: 17.69, longestRunKm: 17, avgPaceSecPerKm: 364, ageYears: 32))
        #expect(request.planKind == .tenK)
        #expect(request.source == .suggested(.tenK))
        #expect(request.today == today)
    }

    @Test func aGeneratorErrorSavesNothing() async {
        let plans = FakePlanRepository()
        await #expect(throws: PlanCreationError.generationFailed) {
            _ = try await useCase(FakeGenerator(.failure(FakeStorageError())), plans: plans).execute(setup, source: .custom)
        }
        #expect(await plans.saveCount == 0)
    }

    @Test func aRuleViolationSavesNothing() async {
        let plans = FakePlanRepository()
        var broken = validPlan()
        broken = TrainingPlan(id: "", createdAt: .distantPast, generatedBy: "fake", planKind: .tenK, race: setup,
                              planStart: broken.planStart, weeks: Array(broken.weeks.dropLast())) // no taper at the end
        await #expect(throws: PlanCreationError.invalidPlan([.lastWeekNotTaper])) {
            _ = try await useCase(FakeGenerator(.success(broken)), plans: plans).execute(setup, source: .custom)
        }
        #expect(await plans.saveCount == 0)
    }

    @Test func anInvalidSetupNeverReachesTheGenerator() async {
        let generator = FakeGenerator(.success(validPlan()))
        let bad = RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: setup.raceDate, trainingDays: [.tuesday])
        await #expect(throws: PlanCreationError.invalidSetup([.tooFewDays])) {
            _ = try await useCase(generator, plans: FakePlanRepository()).execute(bad, source: .custom)
        }
        #expect(await generator.requests.isEmpty)
    }

    @Test func aFailedSaveIsReported() async {
        await #expect(throws: PlanCreationError.saveFailed) {
            _ = try await useCase(FakeGenerator(.success(validPlan())), plans: FakePlanRepository(failsOnSave: true)).execute(setup, source: .custom)
        }
    }

    @Test func suggestedDraftPrefillsDistanceDateAndRuns() {
        let suggestion = PlanSuggestion(plan: .halfMarathon, label: .stretch, reason: "", readiness: 0.7, weeks: 12, runsPerWeek: 4,
                                        suggestedRaceDate: Date(timeIntervalSince1970: 1_798_934_400)) // 2027-01-03T00:00Z
        let draft = RaceSetupDraft.suggested(suggestion, calendar: calendar)
        #expect(draft.distanceKm == 21.1)
        #expect(draft.raceDate == LocalDate(year: 2027, month: 1, day: 3))
        #expect(draft.runsPerWeek == 4)
        #expect(draft.planSource == .suggested(.halfMarathon))
        #expect(RaceSetupDraft.custom.distanceKm == nil)
        #expect(RaceSetupDraft.custom.raceDate == nil)
    }
}
