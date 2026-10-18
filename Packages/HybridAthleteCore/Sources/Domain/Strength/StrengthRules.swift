import Foundation

/// Every number behind strength sessions: doses by phase, placement limits, the
/// template's weekly counts and completion. A first draft; edit freely.
public enum StrengthRules {
    /// Strength sessions a week may hold (the model decides within this).
    public static let maxPerWeek = 3
    public static let minutesRange = 15...60
    /// A Health strength, core or HIIT workout at least this long completes a session.
    public static let minimumWorkoutMinutes = 15.0

    /// Run types that never share a day with strength, nor follow it the day after (long).
    public static let hardRunTypes: Set<SessionType> = [.tempo, .threshold, .intervals, .long]

    /// sets x reps by phase.
    public static func repDose(_ phase: PlanPhase) -> (sets: Int, reps: Int) {
        switch phase {
        case .base: (2, 12)
        case .build: (3, 10)
        case .peak: (3, 6)
        case .taper: (2, 6)
        }
    }

    /// sets x seconds by phase.
    public static func holdDose(_ phase: PlanPhase) -> (sets: Int, seconds: Int) {
        switch phase {
        case .base: (2, 30)
        case .build: (3, 40)
        case .peak: (3, 45)
        case .taper: (2, 30)
        }
    }

    /// The load cue shown with the session.
    public static func effort(_ phase: PlanPhase, focus: StrengthFocus) -> String {
        if focus == .mobility { return "Easy range of motion, never into pain" }
        switch phase {
        case .base: return "Bodyweight or light weight, 3 reps in reserve"
        case .build: return "Moderate weight, 2 reps in reserve"
        case .peak: return "Heavier weight, slow and controlled, 2 reps in reserve"
        case .taper: return "Light and crisp, stop well before tired"
        }
    }

    // MARK: Template

    /// How many strength sessions the template plans in a week of this phase.
    public static func templateCount(_ phase: PlanPhase, isRaceWeek: Bool) -> Int {
        if isRaceWeek { return 0 }
        switch phase {
        case .base, .build: return 2
        case .peak, .taper: return 1
        }
    }

    /// The template's focus for the n-th session (0-based) of a phase.
    public static func templateFocus(_ phase: PlanPhase, slot: Int) -> StrengthFocus {
        let rotation: [StrengthFocus]
        switch phase {
        case .base: rotation = [.lowerBody, .calvesFeet]
        case .build: rotation = [.fullBody, .calvesFeet]
        case .peak: rotation = [.lowerBody]
        case .taper: rotation = [.mobility]
        }
        return rotation[slot % rotation.count]
    }

    public static func templateMinutes(_ focus: StrengthFocus) -> Int {
        focus == .mobility ? 20 : 30
    }
}

/// Turns a day, a focus and minutes into a full strength session. Pure; the
/// template, the draft expander and plan adjustments all use it.
public enum StrengthContentBuilder {
    public static func session(
        date: LocalDate, focus: StrengthFocus, minutes: Int, phase: PlanPhase, variant: StrengthVariant, id: String? = nil
    ) -> StrengthSession {
        StrengthSession(
            id: id ?? StrengthSession.id(for: date),
            originalDate: date,
            date: date,
            focus: focus,
            variant: variant,
            minutes: minutes,
            effort: StrengthRules.effort(phase, focus: focus),
            exercises: StrengthLibrary.exercises(focus, variant).map { exercise(phase: phase, $0) },
            isMissed: false
        )
    }

    static func exercise(phase: PlanPhase, _ item: LibraryExercise) -> StrengthExercise {
        let sets: Int
        var reps: Int?
        var seconds: Int?
        switch item.dosing {
        case .reps:
            let dose = StrengthRules.repDose(phase)
            (sets, reps) = (dose.sets, dose.reps)
        case .hold:
            let dose = StrengthRules.holdDose(phase)
            (sets, seconds) = (dose.sets, dose.seconds)
        case .fixedReps(let fixedSets, let fixedReps):
            (sets, reps) = (fixedSets, fixedReps)
        case .fixedHold(let fixedSets, let fixedSeconds):
            (sets, seconds) = (fixedSets, fixedSeconds)
        }
        return StrengthExercise(
            name: item.name, sets: sets, reps: reps, seconds: seconds, perSide: item.perSide, equipment: item.equipment, howTo: item.howTo
        )
    }

    /// Sessions of the same focus alternate A, B, A, ... in date order.
    /// `earlier` counts sessions of each focus that come before these (for an
    /// adjustment in the middle of a plan).
    public static func variants(
        for items: [(date: LocalDate, focus: StrengthFocus)], earlier: [StrengthFocus: Int] = [:]
    ) -> [LocalDate: StrengthVariant] {
        var counts = earlier
        var result: [LocalDate: StrengthVariant] = [:]
        for item in items.sorted(by: { $0.date < $1.date }) {
            let count = counts[item.focus, default: 0]
            result[item.date] = StrengthVariant.of(occurrence: count)
            counts[item.focus] = count + 1
        }
        return result
    }
}

/// Where strength may go, checked on dated sessions. Pure.
public enum StrengthPlacement {
    public enum Problem: Sendable, Equatable {
        case notATrainingDay
        case onHardRunDay
        case dayBeforeLongRun
        case inRaceWeek
        case outsideWindow
        case twoOnOneDay
    }

    /// Problems for a strength session on `date`, given the runs of the plan (by
    /// current date), the training days, race day and the plan start.
    public static func problems(
        date: LocalDate, runs: [LocalDate: SessionType], trainingDays: Set<Weekday>, raceDate: LocalDate, planStart: LocalDate
    ) -> [Problem] {
        var problems: [Problem] = []
        if !trainingDays.contains(date.weekday) { problems.append(.notATrainingDay) }
        if let type = runs[date], StrengthRules.hardRunTypes.contains(type) { problems.append(.onHardRunDay) }
        if runs[date.adding(days: 1)] == .long { problems.append(.dayBeforeLongRun) }
        if isInRaceWeek(date, raceDate: raceDate) { problems.append(.inRaceWeek) }
        let lastDay = raceDate.adding(days: -PlanValidator.daysClearBeforeRace)
        if date < planStart || date > lastDay { problems.append(.outsideWindow) }
        return problems
    }

    /// The Monday-to-Sunday week that holds race day.
    public static func isInRaceWeek(_ date: LocalDate, raceDate: LocalDate) -> Bool {
        let monday = raceDate.adding(days: -raceDate.weekday.index)
        return date >= monday && date <= raceDate
    }
}
