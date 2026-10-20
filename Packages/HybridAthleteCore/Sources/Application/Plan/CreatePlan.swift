import Foundation
import Domain

/// Why a plan was not created. Nothing is saved in any of these cases.
public enum PlanCreationError: Error, Sendable, Equatable {
    /// The race distance is outside what the app plans (5 km to a full marathon).
    case raceOutOfScope(distanceKm: Double)
    case invalidSetup([RaceSetupIssue])
    case generationFailed
    /// A model failed (unavailable, quota, network, broken plan...).
    case modelFailed(LLMError)
    case invalidPlan([PlanViolation])
    case saveFailed
}

/// Validates the setup, asks the generator for a plan, checks the plan against
/// the domain rules, stamps it and saves it.
public struct CreatePlan: Sendable {
    private let generator: any PlanGenerator
    private let plans: any PlanRepository
    private let cache: any SnapshotCache
    private let clock: any Clock
    private let calendar: Calendar
    private let makeID: @Sendable () -> String
    private let scope: RaceDistanceScope

    /// `scope` is the app's unless DEBUG `-allowAnyDistance` widens it.
    public init(
        generator: any PlanGenerator,
        plans: any PlanRepository,
        cache: any SnapshotCache,
        clock: any Clock,
        calendar: Calendar,
        makeID: @escaping @Sendable () -> String,
        scope: RaceDistanceScope = .app
    ) {
        self.scope = scope
        self.generator = generator
        self.plans = plans
        self.cache = cache
        self.clock = clock
        self.calendar = calendar
        self.makeID = makeID
    }

    public func execute(_ setup: RaceSetup, source: PlanSource) async throws(PlanCreationError) -> TrainingPlan {
        guard scope.contains(setup.distanceKm) else { throw .raceOutOfScope(distanceKm: setup.distanceKm) }
        let today = LocalDate(clock.now(), calendar: calendar)
        let issues = RaceSetupValidator.issues(setup, today: today, scope: scope)
        guard issues.isEmpty else { throw .invalidSetup(issues) }

        let request = PlanRequest(
            race: setup,
            fitness: await LoadFitnessSummary(cache: cache).execute(),
            today: today,
            planKind: PlanKind.from(distanceKm: setup.distanceKm),
            source: source
        )

        let generated: TrainingPlan
        do {
            generated = try await generator.generate(request)
        } catch let error as LLMError {
            throw .modelFailed(error)
        } catch is CancellationError {
            throw .modelFailed(.cancelled)
        } catch {
            throw .generationFailed
        }

        let violations = PlanValidator.violations(generated, request: request)
        guard violations.isEmpty else { throw .invalidPlan(violations) }

        let plan = generated.stamped(id: makeID(), createdAt: clock.now())
        do {
            try await plans.save(plan)
        } catch {
            throw .saveFailed
        }
        return plan
    }
}

/// The athlete's running numbers from the cached summaries, as generators see
/// them. No cache means no runs.
public struct LoadFitnessSummary: Sendable {
    private let cache: any SnapshotCache

    public init(cache: any SnapshotCache) {
        self.cache = cache
    }

    public func execute() async -> FitnessSummary {
        guard let cached = await cache.load() else { return .none }
        let volume = cached.workouts?.value.volume ?? .none
        return FitnessSummary(
            weeklyKm: volume.weeklyKm,
            longestRunKm: volume.longestRunKm,
            avgPaceSecPerKm: volume.avgPaceSecPerKm,
            vo2Max: cached.vo2Max?.value.latest.value,
            restingHeartRate: cached.restingHeartRate?.value.latest.value,
            ageYears: cached.profile?.value.ageYears
        )
    }
}
