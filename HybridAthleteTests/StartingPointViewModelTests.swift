import Foundation
import Testing
import Domain
import Application
@testable import HybridAthlete

@MainActor
struct StartingPointViewModelTests {
    private func loaded(_ persona: String, onContinue: @escaping @MainActor (RaceSetupDraft) -> Void = { _ in }) async -> StartingPointViewModel {
        let viewModel = CompositionRoot.previewStartingPointViewModel(persona: persona, onContinue: onContinue)
        await viewModel.load()
        return viewModel
    }

    private func stubbed(health: StubHealthDataSource, cache: StubSnapshotCache) -> StartingPointViewModel {
        StartingPointViewModel(
            loadCachedSnapshot: LoadCachedSnapshot(cache: cache),
            refreshHealthSnapshot: RefreshHealthSnapshot(health: health, cache: cache, clock: FixedClock()),
            computeFitnessBaseline: ComputeFitnessBaseline(norms: NoNorms(), clock: FixedClock()),
            suggestPlans: SuggestPlans(clock: FixedClock(), calendar: Calendar(identifier: .gregorian)),
            clock: FixedClock(),
            calendar: Calendar(identifier: .gregorian),
            onContinue: { _ in }
        )
    }

    @Test func firstFillDefaultsToTheBestFitPlan() async {
        // casual: the 5K is the only ready plan.
        let viewModel = await loaded("casual")
        #expect(viewModel.selectedPlan == .fiveK)
        #expect(viewModel.primaryTitle == "Continue with the 5K plan")
        #expect(viewModel.isPrimaryEnabled)
    }

    @Test func aRefreshKeepsThePlanTheUserChose() async {
        let viewModel = await loaded("veteran")
        #expect(viewModel.selectedPlan == .tenK)
        viewModel.select(.halfMarathon)

        await viewModel.refresh()

        #expect(viewModel.selectedPlan == .halfMarathon)
        #expect(viewModel.primaryTitle == "Continue with the Half marathon plan")
    }

    @Test func primaryIsDisabledWhileLoadingButCustomRaceIsNot() {
        let viewModel = CompositionRoot.previewStartingPointViewModel(persona: "casual", slow: true)
        #expect(viewModel.plans == .loading)
        #expect(viewModel.primaryTitle == "Reading your data…")
        #expect(!viewModel.isPrimaryEnabled)
        #expect(viewModel.isCustomRaceEnabled)
        #expect(viewModel.vo2MaxCard == .loading)
        #expect(viewModel.subtitle.showsSpinner)
    }

    @Test func lockedBannerOnlyWhenASectionIsLocked() async {
        let cachedAt = FixedClock.date.addingTimeInterval(-7_200)
        let cachedWorkouts = WorkoutsSummary(
            totalCount: 12, runCount: 4, runHeartRateAverage: 150, personalRecords: [],
            volume: RunningVolume(weeklyKm: 20, longestRunKm: 10)
        )
        let cache = StubSnapshotCache(CachedSnapshot(generatedAt: cachedAt, workouts: CachedSection(value: cachedWorkouts, asOf: cachedAt)))

        let locked = stubbed(health: StubHealthDataSource(lockedWorkouts: true), cache: cache)
        await locked.load()
        #expect(locked.workouts == .locked(cachedValue: cachedWorkouts, asOf: cachedAt))
        #expect(locked.lockedBannerText?.hasPrefix("Health data can't be refreshed while it's locked. Showing what we found at ") == true)
        #expect(locked.subtitle.text.hasPrefix("Based on 12 workouts · updated "))

        let open = stubbed(health: StubHealthDataSource(), cache: StubSnapshotCache())
        await open.load()
        #expect(open.lockedBannerText == nil)
    }

    @Test func cachedDataShowsBeforeTheRefreshFinishes() async {
        let cachedAt = FixedClock.date.addingTimeInterval(-600)
        let cached = WorkoutsSummary(totalCount: 3, runCount: 1, runHeartRateAverage: nil, personalRecords: [], volume: .none)
        let viewModel = stubbed(
            health: StubHealthDataSource(lockedWorkouts: true),
            cache: StubSnapshotCache(CachedSnapshot(generatedAt: cachedAt, workouts: CachedSection(value: cached, asOf: cachedAt)))
        )
        await viewModel.load()
        // Locked keeps showing the cached count and when it was read.
        #expect(viewModel.subtitle.text == "Based on 3 workouts · updated 10 min ago")
    }

    @Test func selectingAnotherPlanOpensRaceSetupWithItsDistanceAndDate() async throws {
        var draft: RaceSetupDraft?
        let viewModel = await loaded("veteran") { draft = $0 }
        viewModel.select(.halfMarathon)
        viewModel.continueWithSelectedPlan()

        guard case .plans(let plans) = viewModel.plans else {
            Issue.record("plans should be loaded")
            return
        }
        let half = try #require(plans.first { $0.plan == .halfMarathon })
        #expect(draft == .suggested(half, calendar: .current))
        #expect(draft?.distanceKm == 21.1)
        #expect(draft?.runsPerWeek == 4)
    }

    @Test func customRaceOpensABlankSetup() async {
        var draft: RaceSetupDraft?
        let viewModel = await loaded("casual") { draft = $0 }
        viewModel.chooseCustomRace()
        #expect(draft == .custom)
    }

    @Test func beginnerSeesTheNoVO2NoteAndABestFitFiveK() async throws {
        let viewModel = await loaded("beginner")
        #expect(viewModel.vo2MaxCard == .message(.init(
            text: "No VO2 max yet. Your Watch estimates it after outdoor runs.",
            showsSettingsHint: true,
            showsRetry: false
        )))
        guard case .plans(let plans) = viewModel.plans else {
            Issue.record("an empty workouts section still offers plans")
            return
        }
        let fiveK = try #require(plans.first)
        #expect(fiveK.plan == .fiveK)
        #expect(fiveK.label == .bestFit)
        #expect(fiveK.reason == "Start here and build your base.")
        #expect(viewModel.selectedPlan == .fiveK)
    }

    @Test func teenSeesWhyVO2HasNoScale() async {
        let viewModel = await loaded("teen")
        guard case .scale(let card) = viewModel.vo2MaxCard else {
            Issue.record("expected a VO2 card")
            return
        }
        #expect(card.note == "Norms start at age 20.")
        #expect(card.betterThan == nil)
    }

    @Test func unsetSexLabelsAllAdults() async {
        let viewModel = await loaded("unsetSex")
        guard case .scale(let vo2) = viewModel.vo2MaxCard, case .scale(let resting) = viewModel.restingHeartRateCard else {
            Issue.record("expected both cards")
            return
        }
        #expect(vo2.note == "Norms need a biological sex set in Health.")
        #expect(resting.statement == "Lower than about 79% of all adults your age. For heart rate, lower is better.")
    }
}

@MainActor
struct ScaleTextTests {
    private func comparison(_ betterThan: Double, _ edge: PercentileEdge, population: NormPopulation = .ageAndSex) -> NormComparison {
        NormComparison(
            result: PercentileResult(betterThanPercent: betterThan, edge: edge),
            population: population, tableId: "t", source: "s"
        )
    }

    @Test func interiorWording() {
        #expect(ScaleText.statement(comparison(86.818, .none), kind: .vo2Max) == "Better than about 87% of people your age and sex.")
        #expect(ScaleText.statement(comparison(98, .none), kind: .restingHeartRate)
            == "Lower than about 98% of people your age and sex. For heart rate, lower is better.")
    }

    @Test func topEdgeWording() {
        // VO2 above the 90th anchor: top 10%. Heart rate below the 1st: top 1%.
        #expect(ScaleText.statement(comparison(90, .top), kind: .vo2Max) == "In the top 10% of people your age and sex.")
        #expect(ScaleText.statement(comparison(99, .top), kind: .restingHeartRate)
            == "In the top 1% of people your age and sex. For heart rate, lower is better.")
    }

    @Test func bottomEdgeWording() {
        #expect(ScaleText.statement(comparison(10, .bottom), kind: .vo2Max) == "In the bottom 10% of people your age and sex.")
        #expect(ScaleText.statement(comparison(1, .bottom), kind: .restingHeartRate)
            == "In the bottom 1% of people your age and sex. For heart rate, lower is better.")
    }

    @Test func unavailableNotes() {
        #expect(ScaleText.note(.ageUnknown) == "Add your date of birth in the Health app.")
        #expect(ScaleText.note(.belowMinimumAge(20)) == "Norms start at age 20.")
        #expect(ScaleText.note(.sexNotSet) == "Norms need a biological sex set in Health.")
        #expect(ScaleText.missingNote(.restingHeartRate) == "No resting heart rate yet.")
    }

    @Test func durations() {
        #expect(StartingPointViewModel.duration(1_287.67) == "21:28")
        #expect(StartingPointViewModel.duration(7_471.14) == "2:04:31")
    }
}
