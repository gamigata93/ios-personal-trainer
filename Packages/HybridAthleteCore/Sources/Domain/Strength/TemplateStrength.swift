import Foundation

/// The template's strength sessions for a plan whose runs are already placed:
/// `StrengthRules.templateCount` a week, on allowed days (training days without a
/// run first, then easy-run days), at least two days apart when possible. The
/// focus follows the phase's rotation across the phase's sessions.
public enum TemplateStrength {
    public static func sessions(for plan: TrainingPlan) -> [StrengthSession] {
        let runs = Dictionary(plan.sessions.map { ($0.date, $0.type) }, uniquingKeysWith: { first, _ in first })
        var picked: [(date: LocalDate, focus: StrengthFocus, phase: PlanPhase)] = []
        // The focus rotates through the phase's list across weeks, so one session a week still varies.
        var countInPhase: [PlanPhase: Int] = [:]
        for week in plan.weeks {
            let isRaceWeek = StrengthPlacement.isInRaceWeek(week.startDate, raceDate: plan.race.raceDate)
            let count = StrengthRules.templateCount(week.phase, isRaceWeek: isRaceWeek)
            guard count > 0 else { continue }
            let candidates = (0..<7).map { week.startDate.adding(days: $0) }
                .filter { date in
                    (runs[date] == nil || runs[date] == .easy)
                        && StrengthPlacement.problems(
                            date: date, runs: runs, trainingDays: plan.race.trainingDays, raceDate: plan.race.raceDate,
                            planStart: plan.planStart
                        ).isEmpty
                }
                .sorted { lhs, rhs in
                    let left = runs[lhs] == nil ? 0 : 1
                    let right = runs[rhs] == nil ? 0 : 1
                    return left != right ? left < right : lhs < rhs
                }
            var days: [LocalDate] = []
            for date in candidates where days.count < count && days.allSatisfy({ abs($0.days(to: date)) >= 2 }) {
                days.append(date)
            }
            for date in candidates where days.count < count && !days.contains(date) {
                days.append(date)
            }
            for date in days.sorted() {
                let slot = countInPhase[week.phase, default: 0]
                picked.append((date, StrengthRules.templateFocus(week.phase, slot: slot), week.phase))
                countInPhase[week.phase] = slot + 1
            }
        }
        let variants = StrengthContentBuilder.variants(for: picked.map { ($0.date, $0.focus) })
        return picked.map { item in
            StrengthContentBuilder.session(
                date: item.date, focus: item.focus, minutes: StrengthRules.templateMinutes(item.focus), phase: item.phase,
                variant: variants[item.date] ?? .a
            )
        }
    }
}
