import Foundation
import Domain

/// Offers the four plans with fit labels and suggested race days.
public struct SuggestPlans: Sendable {
    private let clock: any Clock
    private let calendar: Calendar

    public init(clock: any Clock, calendar: Calendar) {
        self.clock = clock
        self.calendar = calendar
    }

    /// Smallest plan first. Labels come from running volume only.
    public func execute(_ volume: RunningVolume) -> [PlanSuggestion] {
        let now = clock.now()
        return PlanFit.evaluate(volume).map { fit in
            let requirement = PlanFitRules.requirement(for: fit.plan)
            return PlanSuggestion(
                plan: fit.plan,
                label: fit.label,
                reason: fit.reason,
                readiness: fit.readiness,
                weeks: requirement.weeks,
                runsPerWeek: requirement.runsPerWeek,
                suggestedRaceDate: SuggestedRaceDate.date(from: now, plan: fit.plan, calendar: calendar)
            )
        }
    }
}
