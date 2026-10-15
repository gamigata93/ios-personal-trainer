import Foundation

/// The constants behind plan edits. Changing one changes which days the
/// Calendar offers as targets.
public enum PlanEditRules {
    /// Race day and this many days before it minus one are never a target:
    /// 2 means race day and the day before are off limits.
    public static let raceDayBuffer = 2

    /// Session types that count as hard for the back-to-back heads-up.
    public static let hardTypes: Set<SessionType> = [.tempo, .threshold, .intervals, .long]

    /// The first day a session may move to: max(today, plan start).
    public static func earliestTarget(plan: TrainingPlan, today: LocalDate) -> LocalDate {
        max(today, plan.planStart)
    }

    /// The last day a session may move to: race day minus `raceDayBuffer` days.
    public static func latestTarget(plan: TrainingPlan) -> LocalDate {
        plan.race.raceDate.adding(days: -raceDayBuffer)
    }
}
