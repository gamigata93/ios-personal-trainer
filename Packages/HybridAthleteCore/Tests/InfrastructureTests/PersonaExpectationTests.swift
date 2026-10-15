#if DEBUG
import Foundation
import Testing
import Application
import Domain
@testable import Infrastructure

/// Each persona end to end through the real norm data: read, compare, suggest.
struct PersonaExpectationTests {
    private struct FixedClock: Clock {
        func now() -> Date { Date(timeIntervalSinceReferenceDate: 813_240_000) } // Fri 9 Oct 2026, 12:00 UTC
    }

    private struct Outcome {
        let vo2Max: MetricBaseline
        let restingHeartRate: MetricBaseline
        let workouts: WorkoutsSummary?
        let plans: [PlanSuggestion]

        var labels: [FitLabel] { plans.map(\.label) }

        func readiness(_ plan: PlanKind) -> Double {
            plans.first { $0.plan == plan }?.readiness ?? .nan
        }
    }

    /// Refreshes the persona into an in-memory cache, then computes the dashboard
    /// numbers from the cached summaries, as the app does.
    private func run(_ id: String) async throws -> Outcome {
        let persona = try #require(Persona.named(id))
        let clock = FixedClock()
        let cache = InMemorySnapshotCache()
        for await _ in RefreshHealthSnapshot(health: PersonaHealthDataSource(persona: persona, clock: clock), cache: cache, clock: clock).execute() {}
        let cached = await cache.load()

        let baseline = ComputeFitnessBaseline(norms: BundledNormRepository(), clock: clock)
        let profile = cached?.profile?.value
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let workouts = cached?.workouts?.value
        return Outcome(
            vo2Max: await baseline.vo2Max(cached?.vo2Max?.value, profile: profile),
            restingHeartRate: await baseline.restingHeartRate(cached?.restingHeartRate?.value, profile: profile),
            workouts: workouts,
            plans: SuggestPlans(clock: clock, calendar: calendar).execute(workouts?.volume ?? .none)
        )
    }

    private func comparison(_ metric: MetricBaseline) throws -> NormComparison {
        guard case .compared(let comparison) = try #require(metric.norm) else {
            Issue.record("expected a comparison, got \(String(describing: metric.norm))")
            throw CancellationError()
        }
        return comparison
    }

    private func expect(_ comparison: NormComparison, betterThan: Double, band: FitnessBand, edge: PercentileEdge = .none) {
        #expect(abs(comparison.result.betterThanPercent - betterThan) < 0.01)
        #expect(comparison.result.band == band)
        #expect(comparison.result.edge == edge)
    }

    @Test func beginner() async throws {
        let outcome = try await run("beginner")
        // RHR 68, female 20-39: 25 + 25 x (68 - 66) / (74 - 66) = 31.25 -> better than 68.75.
        expect(try comparison(outcome.restingHeartRate), betterThan: 68.75, band: .aboveAverage)
        #expect(outcome.vo2Max.reading == nil)
        #expect(outcome.workouts == nil) // no runs: the workouts section is empty
        #expect(outcome.labels == [.bestFit, .later, .later, .later])
        #expect(outcome.plans[0].reason == PlanFit.startHereReason)
    }

    @Test func casual() async throws {
        let outcome = try await run("casual")
        // VO2 38.0, male 40-49: 60 + 10 x 0.1 / 3.0 = 60.33.
        expect(try comparison(outcome.vo2Max), betterThan: 60.33, band: .aboveAverage)
        // RHR 66, male 40-59: 25 + 25 x 5 / 7 = 42.86 -> better than 57.14.
        expect(try comparison(outcome.restingHeartRate), betterThan: 57.14, band: .average)
        #expect(outcome.labels == [.bestFit, .stretch, .later, .later])
        #expect(abs(outcome.readiness(.fiveK) - 1.2) < 1e-9)
        #expect(abs(outcome.readiness(.tenK) - 0.75) < 1e-9)
        #expect(abs(outcome.readiness(.halfMarathon) - 0.4615) < 1e-3)
    }

    @Test func marathoner() async throws {
        let outcome = try await run("marathoner")
        // VO2 49.0 is above the female 30-39 90th percentile (42.1).
        expect(try comparison(outcome.vo2Max), betterThan: 90, band: .excellent, edge: .top)
        // RHR 52 equals the female 20-39 1st-percentile anchor: better than 99, not an edge.
        expect(try comparison(outcome.restingHeartRate), betterThan: 99, band: .excellent)
        #expect(outcome.labels == [.greatFit, .greatFit, .greatFit, .bestFit])
        #expect(abs(outcome.readiness(.marathon) - 1.3333) < 1e-3)
    }

    @Test func veteran() async throws {
        let outcome = try await run("veteran")
        // VO2 31.0, male 60-69: 70 + 10 x 2.3 / 3.3 = 76.97.
        expect(try comparison(outcome.vo2Max), betterThan: 76.97, band: .aboveAverage)
        // RHR 60 equals the male 60-79 25th anchor: better than 75.
        expect(try comparison(outcome.restingHeartRate), betterThan: 75, band: .aboveAverage)
        #expect(outcome.labels == [.greatFit, .bestFit, .stretch, .later])
        #expect(abs(outcome.readiness(.tenK) - 1.25) < 1e-9)
        #expect(abs(outcome.readiness(.halfMarathon) - 0.769) < 1e-3)
    }

    @Test func teen() async throws {
        let outcome = try await run("teen")
        #expect(outcome.vo2Max.norm == .unavailable(.belowMinimumAge(20)))
        // RHR 58, male 16-19: 10 + 15 x 2 / 5 = 16 -> better than 84.
        expect(try comparison(outcome.restingHeartRate), betterThan: 84, band: .excellent)
        #expect(outcome.labels == [.greatFit, .bestFit, .stretch, .later])
    }

    @Test func unsetSex() async throws {
        let outcome = try await run("unsetSex")
        #expect(outcome.vo2Max.norm == .unavailable(.sexNotSet))
        // RHR 62, all 20-39: 10 + 15 x 5 / 7 = 20.71 -> better than 79.29.
        let resting = try comparison(outcome.restingHeartRate)
        expect(resting, betterThan: 79.29, band: .aboveAverage)
        #expect(resting.population == .allAdults)
        #expect(outcome.labels == [.greatFit, .bestFit, .later, .later])
        #expect(outcome.readiness(.tenK) == 1.0)
        #expect(abs(outcome.readiness(.halfMarathon) - 0.6) < 1e-9)
    }

    @Test func senior() async throws {
        let outcome = try await run("senior")
        // VO2 17.0, female 80-89: 60 + 10 x 1.0 / 1.3 = 67.69.
        expect(try comparison(outcome.vo2Max), betterThan: 67.69, band: .aboveAverage)
        // RHR 70, female 80+: 25 + 25 x 6 / 7 = 46.43 -> better than 53.57.
        expect(try comparison(outcome.restingHeartRate), betterThan: 53.57, band: .average)
        #expect(outcome.labels == [.bestFit, .later, .later, .later])
        #expect(outcome.plans[0].reason == PlanFit.startHereReason)
    }
}
#endif
