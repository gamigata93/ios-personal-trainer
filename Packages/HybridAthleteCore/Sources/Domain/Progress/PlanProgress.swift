import Foundation

/// Where the plan stands on a given day.
public enum PlanStage: Sendable, Equatable {
    /// Today is before the first plan day.
    case notStarted(starts: LocalDate)
    /// Today falls in week `week`, up to and including race day.
    case inProgress(week: Int, phase: PlanPhase)
    /// Race day has passed.
    case finished
}

/// Progress through a plan, derived from the plan, the completed runs and today.
/// Nothing here is stored: it is recomputed whenever any input changes.
public struct PlanProgress: Sendable, Equatable {
    public let plan: TrainingPlan
    public let today: LocalDate
    /// Session id -> the run that completed it.
    public let matches: [String: CompletedRun]
    /// Strength session id -> the strength workout that completed it.
    public let strengthMatches: [String: CompletedStrength]

    public init(plan: TrainingPlan, runs: [CompletedRun], strength: [CompletedStrength] = [], today: LocalDate) {
        self.plan = plan
        self.today = today
        self.matches = SessionCompletionMatcher.match(sessions: plan.sessions, runs: runs)
        self.strengthMatches = StrengthCompletionMatcher.match(sessions: plan.strengthSessions, workouts: strength)
    }

    public func status(of session: PlannedSession) -> SessionStatus {
        SessionStatus.of(date: session.date, isMatched: matches[session.id] != nil, isMissed: session.isMissed, today: today)
    }

    public func status(of session: StrengthSession) -> SessionStatus {
        SessionStatus.of(date: session.date, isMatched: strengthMatches[session.id] != nil, isMissed: session.isMissed, today: today)
    }

    /// The 1-based plan week holding today; nil before the start or after race day.
    public var currentWeekIndex: Int? {
        guard today >= plan.planStart, today <= plan.race.raceDate else { return nil }
        return plan.weeks.first { $0.startDate <= today && today < $0.startDate.adding(days: 7) }?.index
    }

    public var stage: PlanStage {
        if today < plan.planStart { return .notStarted(starts: plan.planStart) }
        if today > plan.race.raceDate { return .finished }
        guard let index = currentWeekIndex, let week = plan.weeks.first(where: { $0.index == index }) else {
            return .finished
        }
        return .inProgress(week: index, phase: week.phase)
    }

    /// Never negative.
    public var daysToRace: Int {
        max(0, today.days(to: plan.race.raceDate))
    }

    /// Sessions before today, plus today's when it is already completed or
    /// marked missed. A missed session is due and not completed.
    /// Strength sessions count the same way.
    public var dueCount: Int {
        plan.sessions.filter { $0.date < today || ($0.date == today && (matches[$0.id] != nil || $0.isMissed)) }.count
            + plan.strengthSessions.filter { $0.date < today || ($0.date == today && (strengthMatches[$0.id] != nil || $0.isMissed)) }.count
    }

    /// Due sessions (runs and strength) that were completed.
    public var completedCount: Int {
        plan.sessions.filter { $0.date <= today && matches[$0.id] != nil }.count
            + plan.strengthSessions.filter { $0.date <= today && strengthMatches[$0.id] != nil }.count
    }

    /// completed / due, or nil while nothing is due yet.
    public var adherence: Double? {
        let due = dueCount
        return due == 0 ? nil : Double(completedCount) / Double(due)
    }

    /// The first session strictly after `date` that is not marked missed.
    public func nextSession(after date: LocalDate) -> PlannedSession? {
        plan.sessions.filter { $0.date > date && !$0.isMissed }.min { $0.date < $1.date }
    }
}
