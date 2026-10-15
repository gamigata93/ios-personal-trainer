import Foundation
import Application
import Domain

/// The v1 default plan: deterministic rules, no network. The same request
/// always gives the same plan. All numbers live in `PlanTemplateRules`.
public struct TemplatePlanGenerator: PlanGenerator {
    private typealias Rules = PlanTemplateRules

    public init() {}

    public func generate(_ request: PlanRequest) async throws -> TrainingPlan {
        Self.plan(for: request)
    }

    /// The id and creation date are placeholders; `CreatePlan` stamps the real ones.
    static func plan(for request: PlanRequest) -> TrainingPlan {
        let start = request.planStart
        let weekCount = PlanCalendar.weekCount(from: start, to: request.race.raceDate)
        let phases = Self.phases(kind: request.planKind, weeks: weekCount)
        let targets = Self.weeklyTargets(phases: phases, kind: request.planKind, baselineKm: request.fitness.weeklyKm)

        var buildIndex = 0
        let weeks: [PlanWeek] = (0..<weekCount).map { offset in
            let phase = phases[offset]
            if phase == .build { buildIndex += 1 }
            let weekStart = start.adding(days: offset * 7)
            let context = WeekContext(
                request: request,
                index: offset + 1,
                start: weekStart,
                phase: phase,
                buildIndex: buildIndex,
                target: targets[offset],
                isRaceWeek: offset == weekCount - 1
            )
            return PlanWeek(index: offset + 1, startDate: weekStart, phase: phase, targetKm: targets[offset], sessions: Self.sessions(context))
        }

        return TrainingPlan(
            id: "",
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            generatedBy: Rules.generatedBy,
            planKind: request.planKind,
            race: request.race,
            planStart: start,
            weeks: weeks
        )
    }

    // MARK: Phases and weekly targets

    /// Base, build, peak and taper week by week. Peak, then taper, shrink toward 1
    /// while taper + peak + 2 is more than the plan has weeks.
    static func phases(kind: PlanKind, weeks: Int) -> [PlanPhase] {
        var taper = Rules.taperWeeks(kind)
        var peak = Rules.peakWeeks(kind)
        while taper + peak + 2 > weeks, peak > 1 || taper > 1 {
            if peak > 1 { peak -= 1 } else { taper -= 1 }
        }
        let remaining = max(0, weeks - taper - peak)
        let base = min(remaining, max(1, Int((Rules.baseShareOfRemaining * Double(remaining)).rounded())))
        let build = remaining - base
        let all = Array(repeating: PlanPhase.base, count: base)
            + Array(repeating: .build, count: build)
            + Array(repeating: .peak, count: peak)
            + Array(repeating: .taper, count: taper)
        return Array(all.suffix(weeks))
    }

    static func weeklyTargets(phases: [PlanPhase], kind: PlanKind, baselineKm: Double) -> [Double] {
        let start = max(baselineKm, Rules.minimumStartKm)
        let peakTarget = Rules.peakTargetKm(kind)
        func load(_ week: Int) -> Double {
            min(peakTarget, start * pow(Rules.weeklyGrowth, Double(week - 1)))
        }
        let lastPeakWeek = phases.lastIndex(of: .peak).map { $0 + 1 } ?? phases.lastIndex { $0 != .taper }.map { $0 + 1 } ?? 1
        let taperFactors = Rules.taperFactors(weeks: phases.filter { $0 == .taper }.count)
        var taperIndex = 0

        return phases.enumerated().map { offset, phase in
            let week = offset + 1
            let km: Double
            switch phase {
            case .taper:
                km = taperFactors[min(taperIndex, taperFactors.count - 1)] * load(lastPeakWeek)
                taperIndex += 1
            case .base, .build:
                km = week % Rules.recoveryEvery == 0 ? Rules.recoveryFactor * load(week - 1) : load(week)
            case .peak:
                km = load(week)
            }
            return roundKm(km)
        }
    }

    // MARK: Sessions

    private struct WeekContext {
        let request: PlanRequest
        let index: Int
        let start: LocalDate
        let phase: PlanPhase
        let buildIndex: Int
        let target: Double
        let isRaceWeek: Bool

        var kind: PlanKind { request.planKind }
    }

    private struct Slot {
        let date: LocalDate
        var type: SessionType
        var km: Double
    }

    private static func sessions(_ week: WeekContext) -> [PlannedSession] {
        let lastDay = week.request.race.raceDate.adding(days: -PlanValidator.daysClearBeforeRace)
        let days = week.request.race.trainingDays.sorted()
            .map { week.start.adding(days: $0.index) }
            .filter { $0 >= week.request.planStart && $0 <= lastDay }
        guard !days.isEmpty else { return [] }

        let slots = week.isRaceWeek ? raceWeekSlots(days, week) : trainingSlots(days, week)
        return slots.sorted { $0.date < $1.date }.map { detail($0, week) }
    }

    /// No long run. The first session is quality at 45% of the week, the rest easy,
    /// all capped at 75% of the race distance. Only as many easy runs as can each
    /// reach the minimum, so a short taper week is never padded out.
    private static func raceWeekSlots(_ days: [LocalDate], _ week: WeekContext) -> [Slot] {
        let cap = floorKm(Rules.raceWeekCapOfRaceDistance * week.request.race.distanceKm)
        let quality = min(roundKm(Rules.raceWeekQualityShare * week.target), cap)
        var slots = [Slot(date: days[0], type: qualityType(week, second: false), km: quality)]
        let remainder = week.target - quality
        let affordable = Int((remainder / Rules.minimumSessionKm).rounded(.down))
        let easyDays = days.dropFirst().prefix(max(0, affordable))
        if !easyDays.isEmpty {
            let km = min(roundKm(remainder / Double(easyDays.count)), cap)
            slots += easyDays.map { Slot(date: $0, type: .easy, km: km) }
        }
        return slots
    }

    private static func trainingSlots(_ allDays: [LocalDate], _ week: WeekContext) -> [Slot] {
        // Fewer sessions when the week is too small for each to reach its minimum.
        let affordable = 1 + max(0, Int(((week.target - Rules.minimumLongRunKm) / Rules.minimumSessionKm).rounded(.down)))
        let count = min(allDays.count, affordable)

        let longDay = allDays.last { $0.weekday == .sunday }
            ?? allDays.last { $0.weekday == .saturday }
            ?? allDays[allDays.count - 1]
        guard count > 1 else {
            return [Slot(date: longDay, type: .long, km: min(week.target, PlanValidator.longRunCapKm(week.kind)))]
        }

        let qualityCount: Int
        switch week.phase {
        case .base, .taper: qualityCount = 1
        case .build, .peak: qualityCount = count >= Rules.sessionsForSecondQuality ? 2 : 1
        }

        let others = allDays.filter { $0 != longDay }
        let firstQuality = others.first { $0.weekday.distance(to: longDay.weekday) > 1 } ?? others[0]
        var qualityDays = [firstQuality]
        if qualityCount == 2 {
            let candidates = others.filter { $0 != firstQuality }
            if let second = candidates.max(by: { lhs, rhs in
                let left = min(lhs.weekday.distance(to: firstQuality.weekday), lhs.weekday.distance(to: longDay.weekday))
                let right = min(rhs.weekday.distance(to: firstQuality.weekday), rhs.weekday.distance(to: longDay.weekday))
                return left != right ? left < right : lhs > rhs // ties go to the earlier day
            }) {
                qualityDays.append(second)
            }
        }
        let easyCount = count - 1 - qualityDays.count
        let easyDays = Array(others.filter { !qualityDays.contains($0) }.prefix(max(0, easyCount)))
        let sessions = 1 + qualityDays.count + easyDays.count

        // Shares of the rounded week target.
        var long = roundKm(Rules.longShare(sessions: sessions) * week.target)
        let quality = roundKm(Rules.qualityShare(sessions: sessions) * week.target)
        var qualities = Array(repeating: quality, count: qualityDays.count)
        var easies = split(week.target - long - qualities.reduce(0, +), into: easyDays.count)
        if easyDays.isEmpty {
            long = week.target - qualities.reduce(0, +) // the long run absorbs rounding
        }

        // Cap the long run; the surplus goes to the easy runs.
        let cap = PlanValidator.longRunCapKm(week.kind)
        if long > cap {
            let surplus = long - cap
            long = cap
            if !easies.isEmpty {
                easies = zip(easies, split(surplus, into: easies.count)).map { $0 + $1 }
            }
        }

        // Every session reaches the minimum, paid for by the long run down to its own
        // minimum, then by easy runs that are above the session minimum.
        func raise(_ km: inout Double, skipping skipped: Int? = nil) {
            guard km < Rules.minimumSessionKm else { return }
            let fromLong = min(Rules.minimumSessionKm - km, max(0, long - Rules.minimumLongRunKm))
            km += fromLong
            long -= fromLong
            for donor in easies.indices where donor != skipped && km < Rules.minimumSessionKm {
                let fromEasy = min(Rules.minimumSessionKm - km, max(0, easies[donor] - Rules.minimumSessionKm))
                km += fromEasy
                easies[donor] -= fromEasy
            }
        }
        for index in qualities.indices { raise(&qualities[index]) }
        for index in easies.indices {
            var km = easies[index]
            raise(&km, skipping: index)
            easies[index] = km
        }

        let types = (0..<qualityDays.count).map { qualityType(week, second: $0 == 1) }
        return [Slot(date: longDay, type: .long, km: long)]
            + zip(qualityDays, zip(types, qualities)).map { Slot(date: $0, type: $1.0, km: $1.1) }
            + zip(easyDays, easies).map { Slot(date: $0, type: .easy, km: $1) }
    }

    /// Splits `total` (a multiple of 0.5) into `parts` rounded shares; the last absorbs rounding.
    private static func split(_ total: Double, into parts: Int) -> [Double] {
        guard parts > 0 else { return [] }
        let each = roundKm(total / Double(parts))
        return Array(repeating: each, count: parts - 1) + [total - each * Double(parts - 1)]
    }

    private static func qualityType(_ week: WeekContext, second: Bool) -> SessionType {
        switch (week.kind, week.phase) {
        case (_, .base), (_, .taper):
            return .tempo
        case (.fiveK, .build), (.tenK, .build):
            let first: SessionType = week.buildIndex % 2 == 1 ? .threshold : .intervals
            return second ? (first == .threshold ? .intervals : .threshold) : first
        case (.fiveK, .peak), (.tenK, .peak):
            return second ? .threshold : .intervals
        case (_, .build):
            return second ? .tempo : .threshold
        case (_, .peak):
            return second ? .threshold : .tempo
        }
    }

    // MARK: Session detail

    /// The shared session content rules (`SessionContentBuilder`).
    private static func detail(_ slot: Slot, _ week: WeekContext) -> PlannedSession {
        SessionContentBuilder.session(
            date: slot.date,
            type: slot.type,
            distanceKm: slot.km,
            phase: week.phase,
            kind: week.kind,
            race: week.request.race,
            avgPaceSecPerKm: week.request.fitness.avgPaceSecPerKm
        )
    }

    // MARK: Rounding

    static func roundKm(_ km: Double) -> Double {
        (km / Rules.roundingKm).rounded() * Rules.roundingKm
    }

    private static func floorKm(_ km: Double) -> Double {
        (km / Rules.roundingKm).rounded(.down) * Rules.roundingKm
    }

}
