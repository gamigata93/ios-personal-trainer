import Foundation

/// The days a suggested change may touch: from today (tomorrow when something
/// today is already done) to the end of next week, never past 2 days before race day.
public struct AdjustmentWindow: Sendable, Equatable, Codable {
    public let start: LocalDate
    public let end: LocalDate

    public init(start: LocalDate, end: LocalDate) {
        self.start = start
        self.end = end
    }

    public func contains(_ date: LocalDate) -> Bool { date >= start && date <= end }

    public var dates: [LocalDate] {
        start > end ? [] : (0...start.days(to: end)).map { start.adding(days: $0) }
    }

    /// Nil when nothing is left to change.
    public static func make(progress: PlanProgress) -> AdjustmentWindow? {
        let plan = progress.plan
        let today = progress.today
        let doneToday = plan.sessions.contains { $0.date == today && progress.matches[$0.id] != nil }
            || plan.strengthSessions.contains { $0.date == today && progress.strengthMatches[$0.id] != nil }
        let start = max(doneToday ? today.adding(days: 1) : today, plan.planStart)
        let nextSunday = today.adding(days: 6 - today.weekday.index + 7)
        let end = min(nextSunday, plan.race.raceDate.adding(days: -PlanValidator.daysClearBeforeRace))
        return start <= end ? AdjustmentWindow(start: start, end: end) : nil
    }
}

/// One run or strength session as a model (or the rules) proposes it for a date.
public struct AdjustmentDraft: Sendable, Equatable {
    public struct Run: Sendable, Equatable {
        public let date: LocalDate
        public let type: SessionType
        public let distanceKm: Double

        public init(date: LocalDate, type: SessionType, distanceKm: Double) {
            self.date = date
            self.type = type
            self.distanceKm = distanceKm
        }
    }

    public struct Strength: Sendable, Equatable {
        public let date: LocalDate
        public let focus: StrengthFocus
        public let minutes: Int

        public init(date: LocalDate, focus: StrengthFocus, minutes: Int) {
            self.date = date
            self.focus = focus
            self.minutes = minutes
        }
    }

    /// The whole new schedule for the window: anything not listed is removed.
    public let runs: [Run]
    public let strength: [Strength]
    /// One sentence for the athlete.
    public let reason: String

    public init(runs: [Run], strength: [Strength], reason: String) {
        self.runs = runs
        self.strength = strength
        self.reason = reason
    }
}

/// A suggested change: the window's sessions before and after, why, and who wrote it.
public struct PlanAdjustment: Sendable, Equatable, Codable {
    public let window: AdjustmentWindow
    public let beforeRuns: [PlannedSession]
    public let beforeStrength: [StrengthSession]
    public let afterRuns: [PlannedSession]
    public let afterStrength: [StrengthSession]
    public let reason: String
    /// "pain, left knee, moderate".
    public let triggerLine: String
    /// "Apple Private Cloud", "Apple on-device", "rules".
    public let writtenBy: String

    public init(
        window: AdjustmentWindow, beforeRuns: [PlannedSession], beforeStrength: [StrengthSession], afterRuns: [PlannedSession],
        afterStrength: [StrengthSession], reason: String, triggerLine: String, writtenBy: String
    ) {
        self.window = window
        self.beforeRuns = beforeRuns
        self.beforeStrength = beforeStrength
        self.afterRuns = afterRuns
        self.afterStrength = afterStrength
        self.reason = reason
        self.triggerLine = triggerLine
        self.writtenBy = writtenBy
    }

    /// One row per day whose sessions change, oldest first.
    public var changes: [AdjustmentChange] {
        window.dates.compactMap { date in
            let before = AdjustmentChange.describe(run: beforeRuns.first { $0.date == date }, strength: beforeStrength.first { $0.date == date })
            let after = AdjustmentChange.describe(run: afterRuns.first { $0.date == date }, strength: afterStrength.first { $0.date == date })
            return before == after ? nil : AdjustmentChange(date: date, before: before, after: after)
        }
    }

    /// Nothing would change.
    public var isEmpty: Bool { changes.isEmpty }

    /// The plan with the window's sessions replaced.
    public func applied(to plan: TrainingPlan) -> TrainingPlan {
        let keptRuns = plan.sessions.filter { session in !beforeRuns.contains { $0.id == session.id } }
        let keptStrength = plan.strengthSessions.filter { item in !beforeStrength.contains { $0.id == item.id } }
        return plan.replacing(sessions: keptRuns + afterRuns, strength: keptStrength + afterStrength)
    }
}

/// "Wed 28 Oct: Tempo run 7.0 km → Easy run 5.5 km".
public struct AdjustmentChange: Sendable, Equatable {
    public let date: LocalDate
    public let before: String
    public let after: String

    /// "Tempo run 7.0 km + Strength: Core A", or "Rest".
    static func describe(run: PlannedSession?, strength: StrengthSession?) -> String {
        let parts = [run.map { "\($0.name) \(SessionFormat.distanceText(km: $0.distanceKm))" }, strength.map(\.name)].compactMap { $0 }
        return parts.isEmpty ? "Rest" : parts.joined(separator: " + ")
    }

    public var line: String { "\(HomeFormat.shortDate(date)): \(before) \u{2192} \(after)" }
}
