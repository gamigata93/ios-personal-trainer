import Foundation
import Domain

/// The heart-rate profile from the cached summaries: max = the observed max of
/// recent runs, else 220 minus age; resting = the latest resting heart rate.
/// Nil when either is unknown.
public struct LoadHeartRateProfile: Sendable {
    private let snapshots: any SnapshotCache
    private let recovery: any RecoveryCache

    public init(snapshots: any SnapshotCache, recovery: any RecoveryCache) {
        self.snapshots = snapshots
        self.recovery = recovery
    }

    public func execute() async -> HeartRateProfile? {
        let snapshot = await snapshots.load()
        let maxHr = ObservedMaxHeartRate.maxHr(
            observed: snapshot?.workouts?.value.observedMaxHr,
            ageYears: snapshot?.profile?.value.ageYears
        )
        let latestDay = await recovery.load()?.restingHr.max { $0.date < $1.date }
        let restingHr = latestDay?.bpm ?? snapshot?.restingHeartRate?.value.latest.value
        return HeartRateProfile.make(maxHr: maxHr, restingHr: restingHr)
    }
}

/// Puts together everything one note may use: the reviewed run, the program
/// (with the recent sessions' verdicts from their cached analyses) and the
/// recovery around the run date. Never reads Health.
public struct BuildWorkoutNoteRequest: Sendable {
    private let profile: @Sendable () async -> HeartRateProfile?
    private let sleep: any SleepCache
    private let recovery: any RecoveryCache
    private let analyses: any WorkoutAnalysisRepository
    private let clock: any Clock
    private let calendar: Calendar

    public init(
        profile: @escaping @Sendable () async -> HeartRateProfile?,
        sleep: any SleepCache,
        recovery: any RecoveryCache,
        analyses: any WorkoutAnalysisRepository,
        clock: any Clock,
        calendar: Calendar
    ) {
        self.profile = profile
        self.sleep = sleep
        self.recovery = recovery
        self.analyses = analyses
        self.clock = clock
        self.calendar = calendar
    }

    public var today: LocalDate { LocalDate(date: clock.now(), calendar: calendar) }

    public func execute(plan: TrainingPlan, runs: [CompletedRun], session: PlannedSession, run: CompletedRun, analysis: WorkoutAnalysis) async -> WorkoutNoteRequest {
        let today = today
        let profile = await profile()
        let review = WorkoutReview(session: session, run: run, analysis: analysis, profile: profile)
        let verdicts = await recentVerdicts(plan: plan, runs: runs, today: today, runDate: run.localDate, profile: profile, current: review)
        let nights = await sleep.load()?.nights ?? []
        let cachedRecovery = await recovery.load()
        return WorkoutNoteRequest(
            review: review,
            planSource: plan.generatedBy,
            program: ProgramStatus.make(plan: plan, runs: runs, verdicts: verdicts, today: today, runDate: run.localDate),
            recovery: RecoveryContext.facts(
                runDate: run.localDate,
                sleepNights: nights,
                hrvNights: cachedRecovery?.hrv ?? [],
                restingDays: cachedRecovery?.restingHr ?? []
            )
        )
    }

    /// Verdicts for the recent completed sessions that have a cached analysis.
    private func recentVerdicts(
        plan: TrainingPlan, runs: [CompletedRun], today: LocalDate, runDate: LocalDate, profile: HeartRateProfile?, current: WorkoutReview
    ) async -> [String: WorkoutVerdict] {
        let progress = PlanProgress(plan: plan, runs: runs, today: today)
        let recent = plan.sessions
            .filter { $0.date <= runDate && progress.matches[$0.id] != nil }
            .sorted { $0.date > $1.date }
            .prefix(AnalysisRules.recentSessionsInFacts)
        var verdicts: [String: WorkoutVerdict] = [current.session.id: current.verdict]
        for session in recent where verdicts[session.id] == nil {
            guard
                let run = progress.matches[session.id],
                let analysis = try? await analyses.analysis(runId: run.id)
            else { continue }
            verdicts[session.id] = WorkoutReview(session: session, run: run, analysis: analysis, profile: profile).verdict
        }
        return verdicts
    }
}
