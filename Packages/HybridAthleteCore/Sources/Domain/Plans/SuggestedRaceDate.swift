import Foundation

/// Proposes a race day: the plan's length from now, then the next Sunday.
public enum SuggestedRaceDate {
    /// Start of the suggested race day in `calendar`'s time zone. A date that is
    /// already a Sunday is kept.
    public static func date(from now: Date, plan: PlanKind, calendar: Calendar) -> Date? {
        let weeks = PlanFitRules.requirement(for: plan).weeks
        guard let end = calendar.date(byAdding: .day, value: weeks * 7, to: calendar.startOfDay(for: now)) else {
            return nil
        }
        let sunday = 1 // Gregorian weekday numbering
        if calendar.component(.weekday, from: end) == sunday {
            return end
        }
        return calendar.nextDate(after: end, matching: DateComponents(weekday: sunday), matchingPolicy: .nextTime)
    }
}

/// One plan as offered on the starting-point screen.
public struct PlanSuggestion: Sendable, Equatable {
    public let plan: PlanKind
    public let label: FitLabel
    public let reason: String
    public let readiness: Double
    public let weeks: Int
    public let runsPerWeek: Int
    public let suggestedRaceDate: Date?

    public init(
        plan: PlanKind,
        label: FitLabel,
        reason: String,
        readiness: Double,
        weeks: Int,
        runsPerWeek: Int,
        suggestedRaceDate: Date?
    ) {
        self.plan = plan
        self.label = label
        self.reason = reason
        self.readiness = readiness
        self.weeks = weeks
        self.runsPerWeek = runsPerWeek
        self.suggestedRaceDate = suggestedRaceDate
    }
}
