import Foundation
import Testing
import Domain
import Application
@testable import HybridAthlete

@MainActor
struct RootViewModelTests {
    private func makeRoot(status: HealthAuthorizationRequestStatus, hasPlan: Bool) -> RootViewModel {
        let health = StubHealthDataSource(status: status)
        let cache = StubSnapshotCache()
        let plans = StubPlans(hasPlan: hasPlan)
        return RootViewModel(
            resolveLaunchRoute: LaunchRouteResolver(health: health, plans: plans),
            refreshHealthSnapshot: RefreshHealthSnapshot(health: health, cache: cache, clock: FixedClock()),
            makeConnectHealth: { onFinished in
                ConnectHealthViewModel(requestHealthAccess: RequestHealthAccess(health: health), onFinished: onFinished)
            },
            makeStartingPoint: { onContinue in
                StartingPointViewModel(
                    loadCachedSnapshot: LoadCachedSnapshot(cache: cache),
                    refreshHealthSnapshot: RefreshHealthSnapshot(health: health, cache: cache, clock: FixedClock()),
                    computeFitnessBaseline: ComputeFitnessBaseline(norms: NoNorms(), clock: FixedClock()),
                    suggestPlans: SuggestPlans(clock: FixedClock(), calendar: Calendar(identifier: .gregorian)),
                    clock: FixedClock(),
                    calendar: Calendar(identifier: .gregorian),
                    onContinue: onContinue
                )
            },
            makeRaceSetup: { draft, onBuild, onBack in
                RaceSetupViewModel(draft: draft, validateRaceSetup: ValidateRaceSetup(clock: FixedClock(), calendar: Calendar(identifier: .gregorian)),
                                   calendar: Calendar(identifier: .gregorian), onBuild: onBuild, onBack: onBack)
            },
            makeGenerating: { setup, source, onSuccess, onBack in
                GeneratingViewModel(
                    setup: setup, source: source,
                    createPlan: CreatePlan(generator: FailingGenerator(), plans: plans, cache: cache, clock: FixedClock(),
                                           calendar: Calendar(identifier: .gregorian), makeID: { "id" }),
                    onSuccess: onSuccess, onBack: onBack
                )
            },
            makeHome: { onNoPlan in
                let runs = StubRunsCache()
                let sleep = StubSleepCache()
                let recovery = StubRecoveryCache()
                let calendar = Calendar(identifier: .gregorian)
                let planStore = ActivePlanStore(plans: plans)
                let runStore = CompletedRunsStore(
                    plans: planStore,
                    loadCompletedRuns: LoadCompletedRuns(cache: runs),
                    refreshCompletedRuns: RefreshCompletedRuns(health: health, cache: runs, clock: FixedClock(), calendar: calendar),
                    clock: FixedClock()
                )
                let home = HomeViewModel(
                    plans: planStore,
                    runs: runStore,
                    loadCachedSleep: LoadCachedSleep(cache: sleep),
                    loadCachedRecovery: LoadCachedRecovery(cache: recovery),
                    refreshRecoverySection: RefreshRecoverySection(
                        refreshSleep: RefreshSleep(health: health, cache: sleep, clock: FixedClock(), calendar: calendar),
                        loadCachedSleep: LoadCachedSleep(cache: sleep),
                        refreshRecovery: RefreshRecovery(health: health, cache: recovery, clock: FixedClock(), calendar: calendar)
                    ),
                    getHomeOverview: GetHomeOverview(
                        clock: FixedClock(), calendar: calendar,
                        sleepOverview: GetSleepOverview(calendar: calendar, locale: Locale(identifier: "en_GB")),
                        recoveryOverview: GetRecoveryOverview()
                    ),
                    deleteActivePlan: DeleteActivePlan(plans: plans),
                    clock: FixedClock(),
                    onNoPlan: onNoPlan
                )
                return MainScreens(
                    plans: planStore,
                    runs: runStore,
                    home: home,
                    calendar: CalendarViewModel(plans: planStore, runs: runStore, getCalendarMonth: GetCalendarMonth(clock: FixedClock(), calendar: calendar)),
                    makeSessionDetail: { id in
                        SessionDetailViewModel(sessionID: id, plans: planStore, runs: runStore, getSessionDetail: GetSessionDetail(clock: FixedClock(), calendar: calendar))
                    }
                )
            }
        )
    }

    @Test func neverRequestedOpensConnectHealth() async {
        let root = makeRoot(status: .shouldRequest, hasPlan: true)
        await root.start()
        #expect(root.route == .connectHealth)
    }

    @Test func connectingMovesToTheStartingPoint() async {
        let root = makeRoot(status: .shouldRequest, hasPlan: false)
        await root.start()
        await root.connectHealth?.allow()
        #expect(root.route == .startingPoint)
        #expect(root.startingPoint != nil)
    }

    @Test func requestedWithoutPlanOpensTheStartingPoint() async {
        let root = makeRoot(status: .alreadyRequested, hasPlan: false)
        await root.start()
        #expect(root.route == .startingPoint)
    }

    @Test func aPlanOpensHome() async {
        let root = makeRoot(status: .alreadyRequested, hasPlan: true)
        await root.start()
        #expect(root.route == .home)
    }

    @Test func customRaceGoesToRaceSetupAndBack() async {
        let root = makeRoot(status: .alreadyRequested, hasPlan: false)
        await root.start()
        root.startingPoint?.chooseCustomRace()
        #expect(root.route == .raceSetup)
        #expect(root.raceSetup?.draft == .custom)
        root.raceSetup?.back()
        #expect(root.route == .startingPoint)
    }

    @Test func aFailedBuildCanGoBackToTheSameSetup() async throws {
        let root = makeRoot(status: .alreadyRequested, hasPlan: false)
        await root.start()
        root.startingPoint?.chooseCustomRace()
        let setup = try #require(root.raceSetup)
        setup.distanceText = "10"
        setup.setRaceDay(try #require(LocalDate(FixedClock.date, calendar: Calendar(identifier: .gregorian)).adding(days: 70).date(in: Calendar(identifier: .gregorian))))
        setup.toggle(.tuesday)
        setup.toggle(.sunday)
        setup.build()
        #expect(root.route == .generating)

        await root.generating?.start()
        #expect(root.generating?.phase == .failed("Your plan couldn't be built. Try again."))
        root.generating?.backToSetup()
        #expect(root.route == .raceSetup)
        #expect(root.raceSetup === setup)
        #expect(root.raceSetup?.distanceText == "10")
    }
}
