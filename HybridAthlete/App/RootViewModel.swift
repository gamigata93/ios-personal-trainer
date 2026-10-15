import Foundation
import Observation
import Domain
import Application

/// Picks the launch screen, walks onboarding, and keeps Health data fresh.
@MainActor
@Observable
final class RootViewModel {
    typealias ConnectHealthFactory = @MainActor (
        _ onFinished: @escaping @MainActor () -> Void
    ) -> ConnectHealthViewModel

    typealias StartingPointFactory = @MainActor (
        _ onContinue: @escaping @MainActor (RaceSetupDraft) -> Void
    ) -> StartingPointViewModel

    typealias RaceSetupFactory = @MainActor (
        _ draft: RaceSetupDraft,
        _ onBuild: @escaping @MainActor (RaceSetup, PlanSource) -> Void,
        _ onBack: @escaping @MainActor () -> Void
    ) -> RaceSetupViewModel

    typealias GeneratingFactory = @MainActor (
        _ setup: RaceSetup,
        _ source: PlanSource,
        _ onSuccess: @escaping @MainActor (TrainingPlan) -> Void,
        _ onBack: @escaping @MainActor () -> Void
    ) -> GeneratingViewModel

    typealias HomeFactory = @MainActor (
        _ onNoPlan: @escaping @MainActor () -> Void
    ) -> MainScreens

    /// `nil` until the launch route has been chosen.
    private(set) var route: AppRoute?
    private(set) var connectHealth: ConnectHealthViewModel?
    private(set) var startingPoint: StartingPointViewModel?
    private(set) var raceSetup: RaceSetupViewModel?
    private(set) var generating: GeneratingViewModel?
    /// Home, Calendar and Session detail, sharing the plan and runs.
    private(set) var home: MainScreens?

    private let resolveLaunchRoute: LaunchRouteResolver
    private let refreshHealthSnapshot: RefreshHealthSnapshot
    private let makeConnectHealth: ConnectHealthFactory
    private let makeStartingPoint: StartingPointFactory
    private let makeRaceSetup: RaceSetupFactory
    private let makeGenerating: GeneratingFactory
    private let makeHome: HomeFactory
    /// Runs once before the launch route: the one-time legacy plan import.
    private let prepareStorage: @MainActor () async -> Void
    private var lastHomeRefreshStart: Date?

    init(
        resolveLaunchRoute: LaunchRouteResolver,
        refreshHealthSnapshot: RefreshHealthSnapshot,
        makeConnectHealth: @escaping ConnectHealthFactory,
        makeStartingPoint: @escaping StartingPointFactory,
        makeRaceSetup: @escaping RaceSetupFactory,
        makeGenerating: @escaping GeneratingFactory,
        makeHome: @escaping HomeFactory,
        prepareStorage: @escaping @MainActor () async -> Void = {}
    ) {
        self.prepareStorage = prepareStorage
        self.resolveLaunchRoute = resolveLaunchRoute
        self.refreshHealthSnapshot = refreshHealthSnapshot
        self.makeConnectHealth = makeConnectHealth
        self.makeStartingPoint = makeStartingPoint
        self.makeRaceSetup = makeRaceSetup
        self.makeGenerating = makeGenerating
        self.makeHome = makeHome
    }

    func start() async {
        guard route == nil else { return }
        await prepareStorage()
        switch await resolveLaunchRoute.execute() {
        case .connectHealth: showConnectHealth()
        case .startingPoint: showStartingPoint()
        case .home: await showHome()
        }
    }

    /// Back in the foreground: refresh the visible data if it is old enough.
    func appBecameActive() async {
        switch route {
        case .startingPoint:
            await startingPoint?.refreshIfStale()
        case .home:
            await home?.refreshIfStale()
            if refreshHealthSnapshot.isStale(lastRefreshStart: lastHomeRefreshStart) {
                await refreshInBackground()
            }
        case .connectHealth, .raceSetup, .generating, nil:
            break
        }
    }

    // MARK: Onboarding

    private func showConnectHealth() {
        connectHealth = makeConnectHealth { [weak self] in
            self?.showStartingPoint()
        }
        route = .connectHealth
    }

    /// A fresh starting point (after Connect Health, or after a plan reset).
    func showStartingPoint() {
        connectHealth = nil
        home = nil
        startingPoint = makeStartingPoint { [weak self] draft in
            self?.showRaceSetup(draft)
        }
        route = .startingPoint
    }

    private func showRaceSetup(_ draft: RaceSetupDraft) {
        raceSetup = makeRaceSetup(
            draft,
            { [weak self] setup, source in self?.showGenerating(setup, source) },
            { [weak self] in self?.route = .startingPoint }
        )
        route = .raceSetup
    }

    private func showGenerating(_ setup: RaceSetup, _ source: PlanSource) {
        generating = makeGenerating(
            setup,
            source,
            { [weak self] _ in Task { await self?.showHome() } },
            { [weak self] in self?.route = .raceSetup } // keeps what the user entered
        )
        route = .generating
    }

    // MARK: Home

    private func showHome() async {
        generating = nil
        raceSetup = nil
        startingPoint = nil
        home = makeHome { [weak self] in
            self?.showStartingPoint()
        }
        route = .home
        await refreshInBackground()
    }

    /// Keeps the Health snapshot cache current while Home shows. Home reads its
    /// own completed runs through `RefreshCompletedRuns`.
    private func refreshInBackground() async {
        for await update in refreshHealthSnapshot.execute() {
            if case .started(let date) = update { lastHomeRefreshStart = date }
        }
    }
}
