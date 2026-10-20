import Foundation

/// Every number behind suggested changes. A first draft; edit freely.
public enum AdjustmentRules {
    public static let reasonMaxLength = 160
    /// The rules shorten every run in the window by this share.
    public static let ruleDistanceFactor = 0.8
    public static let ruleMinimumRunKm = 2.0
    public static let roundingKm = 0.5
    /// After severe pain, the rules drop the runs on the window's first days.
    public static let severePainRestDays = 2
    public static let mobilityMinutes = 20
}

/// Why a proposed change cannot be used. Messages double as revision notes.
public enum AdjustmentViolation: Sendable, Equatable {
    case outsideWindow(LocalDate)
    case notATrainingDay(LocalDate)
    case twoRunsOnOneDay(LocalDate)
    case twoStrengthOnOneDay(LocalDate)
    case badDistance(LocalDate)
    case longRunOverCap(LocalDate)
    case moreRunning(newKm: Double, currentKm: Double)
    case strengthMinutes(LocalDate)
    case strength(LocalDate, StrengthPlacement.Problem)
    case reason

    public var message: String {
        switch self {
        case .outsideWindow(let date): "\(date) is outside the days you may change."
        case .notATrainingDay(let date): "\(date) is not a training day."
        case .twoRunsOnOneDay(let date): "There are two runs on \(date)."
        case .twoStrengthOnOneDay(let date): "There are two strength sessions on \(date)."
        case .badDistance(let date): "The run on \(date) has a distance that is zero, negative or over 60 km."
        case .longRunOverCap(let date): "The long run on \(date) is over the long run cap."
        case .moreRunning(let newKm, let currentKm):
            "The new schedule runs \(SessionFormat.oneDecimal(newKm)) km, more than the current \(SessionFormat.oneDecimal(currentKm)) km."
        case .strengthMinutes(let date):
            "The strength session on \(date) is outside \(StrengthRules.minutesRange.lowerBound) to \(StrengthRules.minutesRange.upperBound) minutes."
        case .strength(let date, let problem): "The strength session on \(date) is \(problem.reason)."
        case .reason: "Give one reason sentence of at most \(AdjustmentRules.reasonMaxLength) characters."
        }
    }
}

public enum AdjustmentValidator {
    /// A change never adds running, keeps every rule of the plan, and stays in the window.
    public static func violations(_ draft: AdjustmentDraft, plan: TrainingPlan, window: AdjustmentWindow) -> [AdjustmentViolation] {
        var violations: [AdjustmentViolation] = []
        let trainingDays = plan.race.trainingDays
        let cap = PlanValidator.longRunCapKm(plan.planKind)
        var runDays: Set<LocalDate> = []
        for run in draft.runs {
            if !window.contains(run.date) { violations.append(.outsideWindow(run.date)) }
            if !trainingDays.contains(run.date.weekday) { violations.append(.notATrainingDay(run.date)) }
            if !runDays.insert(run.date).inserted { violations.append(.twoRunsOnOneDay(run.date)) }
            if !(run.distanceKm > 0) || run.distanceKm > PlanValidator.maxSessionKm { violations.append(.badDistance(run.date)) }
            if run.type == .long && run.distanceKm > cap { violations.append(.longRunOverCap(run.date)) }
        }
        let currentKm = plan.sessions.filter { window.contains($0.date) }.map(\.distanceKm).reduce(0, +)
        let newKm = draft.runs.map(\.distanceKm).reduce(0, +)
        if newKm > currentKm + 0.05 { violations.append(.moreRunning(newKm: newKm, currentKm: currentKm)) }

        var runs = Dictionary(plan.sessions.filter { !window.contains($0.date) }.map { ($0.date, $0.type) }, uniquingKeysWith: { first, _ in first })
        for run in draft.runs { runs[run.date] = run.type }
        var strengthDays: Set<LocalDate> = []
        for item in draft.strength {
            if !window.contains(item.date) { violations.append(.outsideWindow(item.date)) }
            if !strengthDays.insert(item.date).inserted { violations.append(.twoStrengthOnOneDay(item.date)) }
            if !StrengthRules.minutesRange.contains(item.minutes) { violations.append(.strengthMinutes(item.date)) }
            violations += StrengthPlacement.problems(
                date: item.date, runs: runs, trainingDays: trainingDays, raceDate: plan.race.raceDate, planStart: plan.planStart
            ).map { .strength(item.date, $0) }
        }
        let reason = draft.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.isEmpty || reason.count > AdjustmentRules.reasonMaxLength { violations.append(.reason) }
        return violations
    }
}

/// Turns a valid draft into a `PlanAdjustment` with full session content.
public enum AdjustmentBuilder {
    public static func make(
        _ draft: AdjustmentDraft, plan: TrainingPlan, window: AdjustmentWindow, triggerLine: String, writtenBy: String
    ) -> PlanAdjustment {
        let pace = planPace(plan)
        let beforeRuns = plan.sessions.filter { window.contains($0.date) }
        let beforeStrength = plan.strengthSessions.filter { window.contains($0.date) }
        // Ids stay unique: a day's own id unless a session outside the window holds it.
        let takenRunIds = Set(plan.sessions.filter { !window.contains($0.date) }.map(\.id))
        let afterRuns = draft.runs.sorted { $0.date < $1.date }.map { run -> PlannedSession in
            let built = SessionContentBuilder.session(
                date: run.date, type: run.type, distanceKm: run.distanceKm, phase: plan.week(containing: run.date)?.phase ?? .base,
                kind: plan.planKind, race: plan.race, avgPaceSecPerKm: pace
            )
            let id = takenRunIds.contains(run.date.description) ? "\(run.date.description)-a" : run.date.description
            return PlannedSession(
                id: id, originalDate: run.date, date: run.date, type: built.type, name: built.name, distanceKm: built.distanceKm,
                estimatedMinutes: built.estimatedMinutes, effort: built.effort, segments: built.segments, note: built.note, isMissed: false
            )
        }
        let takenStrengthIds = Set(plan.strengthSessions.filter { !window.contains($0.date) }.map(\.id))
        var earlier: [StrengthFocus: Int] = [:]
        for item in plan.strengthSessions where item.date < window.start { earlier[item.focus, default: 0] += 1 }
        let variants = StrengthContentBuilder.variants(for: draft.strength.map { ($0.date, $0.focus) }, earlier: earlier)
        let afterStrength = draft.strength.sorted { $0.date < $1.date }.map { item -> StrengthSession in
            let id = StrengthSession.id(for: item.date)
            return StrengthContentBuilder.session(
                date: item.date, focus: item.focus, minutes: item.minutes, phase: plan.week(containing: item.date)?.phase ?? .base,
                variant: variants[item.date] ?? .a, id: takenStrengthIds.contains(id) ? "\(id)-a" : id
            )
        }
        return PlanAdjustment(
            window: window, beforeRuns: beforeRuns, beforeStrength: beforeStrength, afterRuns: afterRuns, afterStrength: afterStrength,
            reason: draft.reason.trimmingCharacters(in: .whitespacesAndNewlines), triggerLine: triggerLine, writtenBy: writtenBy
        )
    }

    /// The pace behind the plan's time estimates (the median of its sessions), for
    /// the new sessions' estimates; nil when the plan has none.
    static func planPace(_ plan: TrainingPlan) -> Double? {
        let paces = plan.sessions.compactMap { session in
            session.estimatedMinutes.map { Double($0 * 60) / session.distanceKm }
        }.filter { $0.isFinite && $0 > 0 }.sorted()
        return paces.isEmpty ? nil : paces[paces.count / 2]
    }
}

/// The deterministic change when no model can write one: hard runs become easy,
/// every run is 20% shorter, leg or back strength becomes mobility, and severe
/// pain drops the runs on the window's first 2 days.
public enum RuleBasedAdjustment {
    public static func draft(plan: TrainingPlan, window: AdjustmentWindow, trigger: AdjustmentTrigger) -> AdjustmentDraft {
        let severePain = trigger.report.kind == .pain && trigger.report.level == .severe
        let restUntil = window.start.adding(days: AdjustmentRules.severePainRestDays)
        let runs = plan.sessions.filter { window.contains($0.date) }.compactMap { session -> AdjustmentDraft.Run? in
            if severePain && session.date < restUntil { return nil }
            let shorter = (session.distanceKm * AdjustmentRules.ruleDistanceFactor / AdjustmentRules.roundingKm).rounded() * AdjustmentRules.roundingKm
            let km = session.distanceKm < AdjustmentRules.ruleMinimumRunKm ? session.distanceKm : max(AdjustmentRules.ruleMinimumRunKm, shorter)
            return AdjustmentDraft.Run(date: session.date, type: .easy, distanceKm: km)
        }
        let area = trigger.report.area
        let affected: Set<StrengthFocus> = area == .lowerBack ? [.lowerBody, .fullBody, .core]
            : (area.isLowerBody ? [.lowerBody, .calvesFeet, .fullBody] : [])
        let strength = plan.strengthSessions.filter { window.contains($0.date) }.map { item in
            affected.contains(item.focus)
                ? AdjustmentDraft.Strength(date: item.date, focus: .mobility, minutes: AdjustmentRules.mobilityMinutes)
                : AdjustmentDraft.Strength(date: item.date, focus: item.focus, minutes: item.minutes)
        }
        let until = HomeFormat.shortDate(window.end)
        let reason = severePain
            ? "Because of the \(trigger.report.line), no running for 2 days, then easy and 20% shorter until \(until)."
            : "Because of the \(trigger.report.line), runs are easy and 20% shorter until \(until)."
        return AdjustmentDraft(runs: runs, strength: strength, reason: String(reason.prefix(AdjustmentRules.reasonMaxLength)))
    }
}

/// The adjustment prompt: the trigger, recent feedback, the window's current
/// schedule and the rules. The model answers with the whole new schedule.
public enum AdjustmentPromptBuilder {
    public static let instructions = """
        You are a running coach adjusting the next days of a training plan after the athlete's feedback.
        Use only the facts and rules given. Return the whole new schedule for the days you may change:
        every run (date, type, distance in km) and every strength session (date, focus, minutes); anything
        you leave out is removed. Never add running: the total distance must not exceed the current total.
        After pain, prefer easy runs, shorter runs or rest, and mobility instead of leg strength. After a
        mild ache, small changes are enough. Give one reason sentence for the athlete, plain words, no
        medical advice.
        """

    public static func build(
        plan: TrainingPlan, window: AdjustmentWindow, trigger: AdjustmentTrigger, feedbackLines: [String], revisionNotes: [String] = []
    ) -> Prompt {
        var facts = [
            "Trigger: " + (trigger.feedback.line ?? trigger.report.line),
            "Race: \(DistanceText.km(plan.race.distanceKm)) km on \(plan.race.raceDate)",
            "Training days: " + plan.race.trainingDays.sorted().map(\.name).joined(separator: ", "),
            "Days you may change: \(window.start) (\(HomeFormat.shortWeekday(window.start.weekday))) to \(window.end) (\(HomeFormat.shortWeekday(window.end.weekday)))",
            "Current schedule:",
        ]
        for date in window.dates {
            let run = plan.sessions.first { $0.date == date }
            let strength = plan.strengthSessions.first { $0.date == date }
            let parts = [
                run.map { "\($0.type.rawValue) run \(SessionFormat.distanceText(km: $0.distanceKm))" },
                strength.map { "strength \($0.focus.promptName) \($0.minutes) min" },
            ].compactMap { $0 }
            let phase = plan.week(containing: date)?.phase.rawValue ?? "base"
            facts.append("\(date) (\(HomeFormat.shortWeekday(date.weekday)), \(phase)): " + (parts.isEmpty ? "rest" : parts.joined(separator: "; ")))
        }
        let total = plan.sessions.filter { window.contains($0.date) }.map(\.distanceKm).reduce(0, +)
        facts += [
            "Current running total: \(SessionFormat.oneDecimal(total)) km (never more)",
            "Run types: easy, tempo, threshold, intervals, long",
            "Long run cap: \(HomeFormat.km(PlanValidator.longRunCapKm(plan.planKind))) km",
            "Strength focus: one of " + StrengthFocus.allCases.map(\.promptName).joined(separator: ", "),
            "Strength minutes: \(StrengthRules.minutesRange.lowerBound) to \(StrengthRules.minutesRange.upperBound), one a day",
            "Strength only on training days, alone or on an easy-run day; never on a tempo, threshold, interval or long-run day, "
                + "never the day before a long run, never in race week",
            "Reason: at most \(AdjustmentRules.reasonMaxLength) characters",
        ]
        if !feedbackLines.isEmpty {
            facts.append("Recent feedback:")
            facts += feedbackLines
        }
        var text = "Adjust the schedule.\n\nFacts:\n" + facts.joined(separator: "\n")
        if !revisionNotes.isEmpty {
            text += "\n\nFix these problems:\n" + revisionNotes.prefix(PlanPromptBuilder.maxRevisionNotes).joined(separator: "\n")
        }
        return Prompt(instructions: instructions, facts: facts, text: text)
    }
}
