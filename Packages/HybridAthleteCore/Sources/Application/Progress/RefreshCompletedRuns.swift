import Foundation
import Domain

/// Reads the plan's runs from Health and keeps the cache current. Runs are read
/// from the plan start to today (or race day, if earlier) and placed on local
/// days with the injected calendar.
public struct RefreshCompletedRuns: Sendable {
    private let health: any HealthDataSource
    private let strengthSource: (any StrengthWorkoutSource)?
    private let cache: any CompletedRunsCache
    private let clock: any Clock
    private let calendar: Calendar

    /// Without a `strengthSource`, no strength workouts are read.
    public init(
        health: any HealthDataSource, strength: (any StrengthWorkoutSource)? = nil, cache: any CompletedRunsCache, clock: any Clock,
        calendar: Calendar
    ) {
        self.health = health
        self.strengthSource = strength
        self.cache = cache
        self.clock = clock
        self.calendar = calendar
    }

    /// Whether a refresh that started at `lastRefreshStart` is old enough to repeat
    /// on returning to the foreground.
    public func isStale(lastRefreshStart: Date?) -> Bool {
        guard let lastRefreshStart else { return true }
        return clock.now().timeIntervalSince(lastRefreshStart) >= RefreshHealthSnapshot.foregroundRefreshInterval
    }

    /// Fresh runs, saved to the cache. Locked returns the cached runs with their
    /// time; any other failure returns the cache untouched. Never throws.
    public func execute(for plan: TrainingPlan) async -> CompletedRunsResult {
        let today = LocalDate(date: clock.now(), calendar: calendar)
        let end = min(today, plan.race.raceDate)
        guard end >= plan.planStart else {
            return CompletedRunsResult(runs: [], asOf: clock.now(), source: .fresh)
        }
        do {
            let summaries = try await mappingHealthErrors {
                try await health.runningWorkouts(from: plan.planStart, to: end)
            }
            let runs = summaries
                .map { summary in
                    CompletedRun(
                        id: summary.id,
                        localDate: LocalDate(date: summary.startDate, calendar: calendar),
                        distanceKm: summary.distanceMeters / 1_000,
                        durationSeconds: summary.durationSeconds,
                        avgHr: summary.averageHeartRate,
                        maxHr: summary.maxHeartRate
                    )
                }
                .filter { $0.localDate >= plan.planStart && $0.localDate <= end }
                .sorted { ($0.localDate, $0.id) < ($1.localDate, $1.id) }
            let strength = await strengthWorkouts(plan: plan, end: end)
            let now = clock.now()
            try? await cache.save(CachedRuns(generatedAt: now, planId: plan.id, runs: runs, strength: strength))
            return CompletedRunsResult(runs: runs, strength: strength, asOf: now, source: .fresh)
        } catch {
            let cached = await cache.runs(for: plan)
            return CompletedRunsResult(
                runs: cached?.runs ?? [],
                strength: cached?.strength ?? [],
                asOf: cached?.generatedAt,
                source: error == .locked ? .locked : .cache
            )
        }
    }

    /// Strength workouts on the plan's days. A failure here never fails the runs:
    /// the cached ones are kept.
    private func strengthWorkouts(plan: TrainingPlan, end: LocalDate) async -> [CompletedStrength] {
        guard let strengthSource else { return [] }
        do {
            return try await strengthSource.strengthWorkouts(from: plan.planStart, to: end)
                .map { CompletedStrength(
                    id: $0.id, localDate: LocalDate(date: $0.startDate, calendar: calendar), durationSeconds: $0.durationSeconds, kind: $0.kind
                ) }
                .filter { $0.localDate >= plan.planStart && $0.localDate <= end }
                .sorted { ($0.localDate, $0.id) < ($1.localDate, $1.id) }
        } catch {
            return await cache.runs(for: plan)?.strength ?? []
        }
    }
}
