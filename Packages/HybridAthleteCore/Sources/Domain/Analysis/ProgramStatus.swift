import Foundation

/// Whether the athlete is following the program, on `today`.
public struct ProgramStatus: Sendable, Equatable {
    public struct RecentSession: Sendable, Equatable {
        public let date: LocalDate
        public let name: String
        public let plannedKm: Double
        public let doneKm: Double
        public let verdict: WorkoutVerdict

        public init(date: LocalDate, name: String, plannedKm: Double, doneKm: Double, verdict: WorkoutVerdict) {
            self.date = date
            self.name = name
            self.plannedKm = plannedKm
            self.doneKm = doneKm
            self.verdict = verdict
        }
    }

    public struct NextSession: Sendable, Equatable {
        public let date: LocalDate
        public let name: String
        public let km: Double
        /// Days from the note's today: 0 is today, 1 tomorrow.
        public let daysAway: Int

        public init(date: LocalDate, name: String, km: Double, daysAway: Int) {
            self.date = date
            self.name = name
            self.km = km
            self.daysAway = daysAway
        }
    }

    public let completedCount: Int
    public let dueCount: Int
    /// The week holding today; nil before the start or after race day.
    public let weekIndex: Int?
    public let weeksTotal: Int
    public let kmDoneThisWeek: Double
    public let kmPlannedThisWeek: Double
    /// Newest first, at most 3.
    public let recent: [RecentSession]
    public let next: NextSession?
    public let phase: PlanPhase?
    public let daysToRace: Int

    public init(
        completedCount: Int, dueCount: Int, weekIndex: Int?, weeksTotal: Int, kmDoneThisWeek: Double, kmPlannedThisWeek: Double,
        recent: [RecentSession], next: NextSession?, phase: PlanPhase?, daysToRace: Int
    ) {
        self.completedCount = completedCount
        self.dueCount = dueCount
        self.weekIndex = weekIndex
        self.weeksTotal = weeksTotal
        self.kmDoneThisWeek = kmDoneThisWeek
        self.kmPlannedThisWeek = kmPlannedThisWeek
        self.recent = recent
        self.next = next
        self.phase = phase
        self.daysToRace = daysToRace
    }

    /// Whole percent (half up); nil while nothing is due.
    public var adherencePercent: Int? {
        dueCount > 0 ? AnalysisMath.rounded(Double(completedCount) / Double(dueCount) * 100) : nil
    }

    /// `verdicts` holds what is known per session id (from stored analyses);
    /// a completed session without one gets a distance-only verdict. Recent
    /// sessions are dated on or before `runDate` (the described run), never after.
    public static func make(
        plan: TrainingPlan, runs: [CompletedRun], verdicts: [String: WorkoutVerdict], today: LocalDate, runDate: LocalDate
    ) -> ProgramStatus {
        let progress = PlanProgress(plan: plan, runs: runs, today: today)
        let week = progress.currentWeekIndex.flatMap { index in plan.weeks.first { $0.index == index } }
        let done = week?.sessions.compactMap { progress.matches[$0.id]?.distanceKm }.reduce(0, +) ?? 0
        let recent = plan.sessions
            .filter { $0.date <= runDate && progress.matches[$0.id] != nil }
            .sorted { $0.date > $1.date }
            .prefix(AnalysisRules.recentSessionsInFacts)
            .compactMap { session -> RecentSession? in
                guard let run = progress.matches[session.id] else { return nil }
                let verdict = verdicts[session.id]
                    ?? WorkoutAssessment(distance: .check(plannedKm: session.distanceKm, doneKm: run.distanceKm), blocks: []).verdict
                return RecentSession(date: session.date, name: session.name, plannedKm: session.distanceKm, doneKm: run.distanceKm, verdict: verdict)
            }
        return ProgramStatus(
            completedCount: progress.completedCount,
            dueCount: progress.dueCount,
            weekIndex: week?.index,
            weeksTotal: plan.weeks.count,
            kmDoneThisWeek: done,
            kmPlannedThisWeek: week?.totalKm ?? 0,
            recent: Array(recent),
            next: nextSession(progress).map { NextSession(date: $0.date, name: $0.name, km: $0.distanceKm, daysAway: today.days(to: $0.date)) },
            phase: week?.phase,
            daysToRace: progress.daysToRace
        )
    }

    /// The first session on or after today (by its current date) that is still
    /// today or upcoming: not completed, not missed.
    static func nextSession(_ progress: PlanProgress) -> PlannedSession? {
        progress.plan.sessions
            .filter { $0.date >= progress.today && [.today, .upcoming].contains(progress.status(of: $0)) }
            .min { $0.date < $1.date }
    }
}
