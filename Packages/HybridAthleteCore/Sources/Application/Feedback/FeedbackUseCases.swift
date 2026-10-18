import Foundation
import Domain

/// A workout the popup asks about.
public struct FeedbackPrompt: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: FeedbackWorkoutKind
    public let localDate: LocalDate
    /// "Run · Mon 26 Oct", "Strength training · Tue 27 Oct".
    public let title: String
    /// "6.2 km · 34 min", "32 min".
    public let detail: String

    public init(id: String, kind: FeedbackWorkoutKind, localDate: LocalDate, title: String, detail: String) {
        self.id = id
        self.kind = kind
        self.localDate = localDate
        self.title = title
        self.detail = detail
    }
}

/// The workouts to ask about: runs and strength workouts from the last
/// `FeedbackRules.promptWindowDays` days without stored feedback, newest first.
public struct PendingFeedback: Sendable {
    private let feedback: any WorkoutFeedbackRepository
    private let clock: any Clock
    private let calendar: Calendar

    public init(feedback: any WorkoutFeedbackRepository, clock: any Clock, calendar: Calendar) {
        self.feedback = feedback
        self.clock = clock
        self.calendar = calendar
    }

    public func execute(_ workouts: CompletedRunsResult) async -> [FeedbackPrompt] {
        let today = LocalDate(date: clock.now(), calendar: calendar)
        let earliest = today.adding(days: -(FeedbackRules.promptWindowDays - 1))
        guard let answered = try? await feedback.feedback(since: earliest) else { return [] }
        let done = Set(answered.map(\.workoutId))
        let runs = workouts.runs.filter { $0.localDate >= earliest && $0.localDate <= today && !done.contains($0.id) }.map { run in
            FeedbackPrompt(
                id: run.id, kind: .run, localDate: run.localDate, title: "Run · \(HomeFormat.shortDate(run.localDate))",
                detail: "\(SessionFormat.distanceText(km: run.distanceKm)) · \(Int((run.durationSeconds / 60).rounded())) min"
            )
        }
        let strength = workouts.strength.filter { $0.localDate >= earliest && $0.localDate <= today && !done.contains($0.id) }.map { item in
            FeedbackPrompt(
                id: item.id, kind: .strength, localDate: item.localDate, title: "\(item.kind.title) · \(HomeFormat.shortDate(item.localDate))",
                detail: "\(item.minutes) min"
            )
        }
        return (runs + strength).sorted { ($0.localDate, $0.id) > ($1.localDate, $1.id) }
    }
}

/// Saves the popup's answer and says whether it should lead to a suggested plan change.
public struct SaveWorkoutFeedback: Sendable {
    private let feedback: any WorkoutFeedbackRepository

    public init(feedback: any WorkoutFeedbackRepository) {
        self.feedback = feedback
    }

    public func execute(_ new: WorkoutFeedback) async throws -> AdjustmentTrigger? {
        try await feedback.save(new)
        let history = (try? await feedback.feedback(since: new.localDate.adding(days: -FeedbackRules.repeatWindowDays))) ?? []
        return FeedbackRules.trigger(new, history: history)
    }
}

/// Stored feedback for one workout (Session detail's "Your feedback").
public struct LoadWorkoutFeedback: Sendable {
    private let feedback: any WorkoutFeedbackRepository

    public init(feedback: any WorkoutFeedbackRepository) {
        self.feedback = feedback
    }

    public func execute(workoutId: String) async -> WorkoutFeedback? {
        try? await feedback.feedback(workoutId: workoutId)
    }

    /// Lines for a model, from the last `FeedbackRules.linesWindowDays` days.
    public func lines(today: LocalDate) async -> [String] {
        let since = today.adding(days: -FeedbackRules.linesWindowDays)
        return FeedbackRules.lines((try? await feedback.feedback(since: since)) ?? [], today: today)
    }
}

/// Drafts a change for the next days after a trigger: each model in `models`
/// that is available gets two attempts (the second with the problems as
/// revision notes); any `LLMError` moves on to the next; the rules come last.
/// The result is saved as the plan's pending suggestion. Nil when there is
/// nothing to change (no days left, or the change would change nothing).
public struct SuggestPlanAdjustment: Sendable {
    private let adjusting: any PlanAdjustingModel
    private let availability: any ModelAvailabilityChecker
    private let adjustments: any PlanAdjustmentRepository
    private let loadFeedback: LoadWorkoutFeedback
    private let models: [ModelChoice]
    private let clock: any Clock
    private let calendar: Calendar

    /// `models` empty: the rules write every suggestion (DEBUG fakes).
    public init(
        adjusting: any PlanAdjustingModel, availability: any ModelAvailabilityChecker, adjustments: any PlanAdjustmentRepository,
        loadFeedback: LoadWorkoutFeedback, models: [ModelChoice], clock: any Clock, calendar: Calendar
    ) {
        self.adjusting = adjusting
        self.availability = availability
        self.adjustments = adjustments
        self.loadFeedback = loadFeedback
        self.models = models
        self.clock = clock
        self.calendar = calendar
    }

    public func execute(plan: TrainingPlan, workouts: CompletedRunsResult, trigger: AdjustmentTrigger) async throws -> StoredAdjustment? {
        let today = LocalDate(date: clock.now(), calendar: calendar)
        let progress = PlanProgress(plan: plan, runs: workouts.runs, strength: workouts.strength, today: today)
        guard let window = AdjustmentWindow.make(progress: progress) else { return nil }
        let lines = await loadFeedback.lines(today: today)
        let adjustment = await draft(plan: plan, window: window, trigger: trigger, lines: lines)
        guard !adjustment.isEmpty else { return nil }
        return try await adjustments.savePending(planId: plan.id, adjustment: adjustment)
    }

    private func draft(plan: TrainingPlan, window: AdjustmentWindow, trigger: AdjustmentTrigger, lines: [String]) async -> PlanAdjustment {
        for model in models {
            guard await availability.status(for: model).availability.isAvailable else { continue }
            var notes: [String] = []
            for _ in 0..<2 {
                let prompt = AdjustmentPromptBuilder.build(plan: plan, window: window, trigger: trigger, feedbackLines: lines, revisionNotes: notes)
                guard let result = try? await adjusting.adjustPlan(prompt, model: model, purpose: .planAdjustment) else { break }
                let violations = AdjustmentValidator.violations(result.draft, plan: plan, window: window)
                if violations.isEmpty {
                    return AdjustmentBuilder.make(
                        result.draft, plan: plan, window: window, triggerLine: trigger.report.line, writtenBy: Self.writer(model)
                    )
                }
                notes = violations.map(\.message)
            }
        }
        let rules = RuleBasedAdjustment.draft(plan: plan, window: window, trigger: trigger)
        return AdjustmentBuilder.make(rules, plan: plan, window: window, triggerLine: trigger.report.line, writtenBy: "rules")
    }

    /// "Apple Private Cloud", "Apple on-device", "Claude Sonnet 5.5".
    static func writer(_ model: ModelChoice) -> String {
        switch model {
        case .onDevice: "Apple on-device"
        case .privateCloud: "Apple Private Cloud"
        case .anthropic(let claude): "Claude \(claude.displayName)"
        }
    }
}

/// The plan's pending suggestion, and Apply, Keep plan and Undo.
public struct PlanAdjustments: Sendable {
    private let adjustments: any PlanAdjustmentRepository

    public init(adjustments: any PlanAdjustmentRepository) {
        self.adjustments = adjustments
    }

    public func pending(planId: String) async -> StoredAdjustment? {
        try? await adjustments.pending(planId: planId)
    }

    public func apply(id: Int64) async throws {
        try await adjustments.apply(id: id)
    }

    public func dismiss(id: Int64) async throws {
        try await adjustments.dismiss(id: id)
    }

    public func undo(id: Int64) async throws {
        try await adjustments.undo(id: id)
    }
}
