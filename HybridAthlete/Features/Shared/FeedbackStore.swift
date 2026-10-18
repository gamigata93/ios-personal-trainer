import Foundation
import Observation
import Domain
import Application

/// The after-workout popup and the suggested plan change it can lead to. Shared
/// by MainTabView (the sheet), Home (the suggestion card) and Session detail
/// ("Your feedback"). Holds state and calls use cases; the rules live in Domain.
@MainActor
@Observable
final class FeedbackStore {
    /// Where the suggestion stands.
    enum SuggestionState: Equatable {
        case none
        /// A model (or the rules) is drafting a change.
        case checking
        case pending(StoredAdjustment)
        /// Applied; Undo is offered until another suggestion or a dismissal.
        case applied(StoredAdjustment)
        /// The plan changed since it was drafted, or the save failed.
        case failed
    }

    /// The workout the sheet asks about now; nil hides the sheet.
    private(set) var current: FeedbackPrompt?
    /// Stored answer being edited (Session detail's Edit), to prefill the sheet.
    private(set) var editing: WorkoutFeedback?
    private(set) var suggestion: SuggestionState = .none
    /// Set after a severe pain answer, shown once on the suggestion card.
    private(set) var showsSevereMessage = false
    private var queue: [FeedbackPrompt] = []
    /// The sheet was opened from Session detail: Skip only closes it.
    private var isEditing = false

    private let plans: ActivePlanStore
    private let runs: CompletedRunsStore
    private let pending: PendingFeedback
    private let save: SaveWorkoutFeedback
    private let load: LoadWorkoutFeedback
    private let suggest: SuggestPlanAdjustment
    private let adjustments: PlanAdjustments
    private let clock: any Clock
    /// Off for DEBUG fakes unless `-feedbackPopup` (so other UI tests never see the sheet).
    private let asksAutomatically: Bool
    /// Called after an answer, so notes waiting for it can be written.
    var onAnswered: (@MainActor () async -> Void)?

    init(
        plans: ActivePlanStore, runs: CompletedRunsStore, pending: PendingFeedback, save: SaveWorkoutFeedback, load: LoadWorkoutFeedback,
        suggest: SuggestPlanAdjustment, adjustments: PlanAdjustments, clock: any Clock, asksAutomatically: Bool
    ) {
        self.plans = plans
        self.runs = runs
        self.pending = pending
        self.save = save
        self.load = load
        self.suggest = suggest
        self.adjustments = adjustments
        self.clock = clock
        self.asksAutomatically = asksAutomatically
    }

    /// Workouts still waiting for an answer (coach notes wait for them).
    func isAwaiting(_ workoutId: String) -> Bool {
        current?.id == workoutId || queue.contains { $0.id == workoutId }
    }

    // MARK: Refresh

    /// After every runs refresh: queue new workouts and load the pending suggestion.
    func afterRefresh() async {
        if let plan = plans.plan, case .none = suggestion, let stored = await adjustments.pending(planId: plan.id) {
            suggestion = .pending(stored)
        }
        guard asksAutomatically else { return }
        let fresh = await pending.execute(runs.result)
        queue = fresh.filter { $0.id != current?.id }
        if current == nil { showNext() }
    }

    private func showNext() {
        editing = nil
        isEditing = false
        current = queue.isEmpty ? nil : queue.removeFirst()
    }

    // MARK: Answers

    /// Saves the answer, then drafts a suggestion when the rules say so.
    func submit(status: WorkoutFeedback.Status, areas: [AreaReport], note: String?) async {
        guard let prompt = current else { return }
        let feedback = WorkoutFeedback(
            workoutId: prompt.id, workoutKind: prompt.kind, localDate: prompt.localDate, status: status, areas: areas, note: note,
            recordedAt: clock.now()
        )
        let trigger = try? await save.execute(feedback)
        showNext()
        await onAnswered?()
        if feedback.hasSeverePain { showsSevereMessage = true }
        if let trigger { await suggestChange(trigger) }
    }

    /// Closed without answering: never asked again. When editing, only closes.
    func skip() async {
        if isEditing {
            showNext()
            return
        }
        await submit(status: .skipped, areas: [], note: nil)
    }

    /// Opens the sheet for a workout that already has (or never got) an answer.
    func edit(workoutId: String, kind: FeedbackWorkoutKind, localDate: LocalDate, title: String, detail: String) async {
        if let current, current.id != workoutId, !isEditing { queue.insert(current, at: 0) }
        editing = await load.execute(workoutId: workoutId)
        isEditing = true
        current = FeedbackPrompt(id: workoutId, kind: kind, localDate: localDate, title: title, detail: detail)
    }

    /// The stored answer for Session detail.
    func feedback(workoutId: String) async -> WorkoutFeedback? {
        await load.execute(workoutId: workoutId)
    }

    // MARK: Suggestion

    private func suggestChange(_ trigger: AdjustmentTrigger) async {
        guard let plan = plans.plan else { return }
        suggestion = .checking
        if let stored = try? await suggest.execute(plan: plan, workouts: runs.result, trigger: trigger) {
            suggestion = .pending(stored)
        } else {
            suggestion = .none
        }
    }

    func apply() async {
        guard case .pending(let stored) = suggestion else { return }
        do {
            try await adjustments.apply(id: stored.id)
            suggestion = .applied(stored)
        } catch {
            suggestion = .failed
        }
        await plans.reload()
    }

    /// "Keep plan".
    func dismiss() async {
        guard case .pending(let stored) = suggestion else { return }
        try? await adjustments.dismiss(id: stored.id)
        suggestion = .none
        showsSevereMessage = false
    }

    func undo() async {
        guard case .applied(let stored) = suggestion else { return }
        do {
            try await adjustments.undo(id: stored.id)
            suggestion = .none
        } catch {
            suggestion = .failed
        }
        await plans.reload()
    }

    /// Hides the applied, failed or severe-pain message.
    func clearMessage() {
        if case .pending = suggestion {} else if case .checking = suggestion {} else { suggestion = .none }
        showsSevereMessage = false
    }
}
