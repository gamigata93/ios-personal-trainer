import Foundation
import Observation
import Domain
import Application

/// The single shared state for coach notes and workout analyses, read by Home
/// and Session detail. One generation runs at a time (a serial queue) and the
/// same session is never generated twice at once. It holds state and calls use
/// cases; the rules live in Domain.
@MainActor
@Observable
final class CoachNoteStore {
    enum NoteState: Equatable {
        /// No note and nothing running (an older session shows "Write coach note").
        case idle
        case generating
        /// Health is locked; retried after the next refresh.
        case waitingForUnlock
        case ready(SavedCoachNote, stale: Bool)
        /// Generation threw something unexpected.
        case failed
    }

    /// Stored notes by session id.
    private(set) var notes: [String: SavedCoachNote] = [:]
    /// Analyzed sessions by session id.
    private(set) var prepared: [String: PreparedWorkoutNote] = [:]
    /// Sessions whose analysis waits for the phone to be unlocked.
    private(set) var analysisWaiting: Set<String> = []
    private var transient: [String: NoteState] = [:]
    /// Older sessions the user asked a note for (they skip the 7-day window).
    private var requested: Set<String> = []
    private var queue: [(id: String, force: Bool)] = []
    private var inFlight: String?
    private var worker: Task<Void, Never>?
    private var loadedPlanID: String?

    private let plans: ActivePlanStore
    private let runs: CompletedRunsStore
    private let generate: GenerateDetailedCoachNote
    private let prepare: PrepareWorkoutNote
    private let loadNotes: LoadCoachNotes
    private let today: @MainActor () -> LocalDate
    /// A workout whose after-workout popup is still open or queued: its note waits,
    /// so the feedback can be in the facts. Nil: nothing waits.
    var isAwaitingFeedback: (@MainActor (String) -> Bool)?

    init(
        plans: ActivePlanStore,
        runs: CompletedRunsStore,
        generate: GenerateDetailedCoachNote,
        prepare: PrepareWorkoutNote,
        loadNotes: LoadCoachNotes,
        today: @escaping @MainActor () -> LocalDate
    ) {
        self.plans = plans
        self.runs = runs
        self.generate = generate
        self.prepare = prepare
        self.loadNotes = loadNotes
        self.today = today
    }

    // MARK: State

    func state(for sessionId: String) -> NoteState {
        if let transient = transient[sessionId] { return transient }
        guard let note = notes[sessionId] else { return .idle }
        return .ready(note, stale: isStale(note, sessionId: sessionId))
    }

    /// Stale when the matched run or the facts changed since the note was written.
    private func isStale(_ note: SavedCoachNote, sessionId: String) -> Bool {
        if let prepared = prepared[sessionId] {
            return note.isStale(runId: prepared.run.id, inputHash: prepared.inputHash)
        }
        guard let run = matchedRun(sessionId) else { return false }
        return note.runId != run.id
    }

    var isRunning: Bool { worker != nil }

    /// The newest completed session that has a note, for Home.
    var latestCard: LatestCoachNoteCard? {
        guard let plan = plans.plan else { return nil }
        return LatestCoachNoteCard.make(plan: plan, runs: runs.result.runs, notes: notes, today: today())
    }

    // MARK: Loading

    /// Reads the stored notes once per plan.
    func load() async {
        guard let plan = plans.plan, loadedPlanID != plan.id else { return }
        loadedPlanID = plan.id
        notes = await loadNotes.execute(planId: plan.id)
        prepared = [:]
    }

    /// After every completed-runs refresh: write notes for the recent sessions
    /// and retry what waited for an unlock.
    func afterRefresh() async {
        await load()
        for id in autoCandidates() { enqueue(id, force: false) }
        let waiting = transient.filter { $0.value == .waitingForUnlock }.map(\.key) + Array(analysisWaiting)
        for id in Set(waiting) where requested.contains(id) || isWithinAutoWindow(id) {
            transient[id] = nil
            enqueue(id, force: false)
        }
        analysisWaiting = []
    }

    /// Completed sessions without a note from the last 7 days, newest first, at most 3.
    func autoCandidates() -> [String] {
        guard let plan = plans.plan else { return [] }
        let today = today()
        let progress = PlanProgress(plan: plan, runs: runs.result.runs, today: today)
        let earliest = today.adding(days: -AssessmentRules.autoWindowDays)
        return plan.sessions
            .filter { $0.date <= today && $0.date >= earliest && progress.matches[$0.id] != nil }
            .filter { notes[$0.id] == nil && transient[$0.id] != .failed && transient[$0.id] != .generating }
            .filter { session in !(progress.matches[session.id].map { isAwaitingFeedback?($0.id) ?? false } ?? false) }
            .sorted { $0.date > $1.date }
            .prefix(AssessmentRules.maxAutoPerRefresh)
            .map(\.id)
    }

    // MARK: Session detail

    /// Opening Session detail: analyze the run (cached after the first read), then
    /// write a note when there is none and the session is recent or was asked for.
    func open(_ sessionId: String) async {
        await load()
        guard let plan = plans.plan, matchedRun(sessionId) != nil else { return }
        await analyze(sessionId, plan: plan)
        if notes[sessionId] == nil, transient[sessionId] == nil, isWithinAutoWindow(sessionId) || requested.contains(sessionId) {
            enqueue(sessionId, force: false)
        }
    }

    /// "Write coach note" and "Try again".
    func write(_ sessionId: String) {
        requested.insert(sessionId)
        transient[sessionId] = nil
        enqueue(sessionId, force: false)
    }

    /// "Regenerate" and "Update note": replaces the stored note.
    func regenerate(_ sessionId: String) {
        requested.insert(sessionId)
        transient[sessionId] = nil
        enqueue(sessionId, force: true)
    }

    private func analyze(_ sessionId: String, plan: TrainingPlan) async {
        if let current = prepared[sessionId], current.run.id == matchedRun(sessionId)?.id { return }
        switch try? await prepare.execute(plan: plan, runs: runs.result.runs, strength: runs.result.strength, sessionId: sessionId) {
        case .ready(let ready):
            prepared[sessionId] = ready
            analysisWaiting.remove(sessionId)
        case .waitingForUnlock:
            analysisWaiting.insert(sessionId)
        case .notCompleted, nil:
            break
        }
    }

    // MARK: Queue

    private func enqueue(_ sessionId: String, force: Bool) {
        if inFlight == sessionId && !force { return }
        if let index = queue.firstIndex(where: { $0.id == sessionId }) {
            if force { queue[index].force = true }
            return
        }
        queue.append((sessionId, force))
        transient[sessionId] = .generating
        guard worker == nil else { return }
        // Below the screens' own reads: Home and Recovery update first.
        worker = Task(priority: .utility) { [weak self] in
            await Task.yield()
            await self?.drain()
        }
    }

    private func drain() async {
        while !queue.isEmpty {
            let item = queue.removeFirst()
            inFlight = item.id
            await run(item.id, force: item.force)
            inFlight = nil
        }
        worker = nil
    }

    private func run(_ sessionId: String, force: Bool) async {
        guard let plan = plans.plan else {
            transient[sessionId] = nil
            return
        }
        do {
            switch try await generate.execute(plan: plan, runs: runs.result.runs, strength: runs.result.strength, sessionId: sessionId, force: force) {
            case .note(let note):
                notes[sessionId] = note
                transient[sessionId] = nil
                if prepared[sessionId]?.inputHash != note.inputHash { await refreshPrepared(sessionId, plan: plan) }
            case .waitingForUnlock:
                transient[sessionId] = .waitingForUnlock
            case .notCompleted:
                transient[sessionId] = nil
            }
        } catch is CancellationError {
            transient[sessionId] = nil
        } catch {
            transient[sessionId] = .failed
        }
    }

    /// The analysis is cached now, so this never reads Health.
    private func refreshPrepared(_ sessionId: String, plan: TrainingPlan) async {
        if case .ready(let ready) = try? await prepare.execute(plan: plan, runs: runs.result.runs, strength: runs.result.strength, sessionId: sessionId, cachedOnly: true) {
            prepared[sessionId] = ready
        }
    }

    #if DEBUG
    /// The exact prompt (instructions and full facts) for a completed session.
    func factsText(for sessionId: String) async -> String? {
        await load()
        guard let plan = plans.plan, matchedRun(sessionId) != nil else { return nil }
        await analyze(sessionId, plan: plan)
        return prepared[sessionId].map { DetailedNotePromptBuilder.build($0.facts).fullText }
    }
    #endif

    /// Waits for the queue to empty (tests).
    func waitUntilIdle() async {
        while let worker { await worker.value }
    }

    // MARK: Helpers

    private func matchedRun(_ sessionId: String) -> CompletedRun? {
        guard let plan = plans.plan else { return nil }
        return PlanProgress(plan: plan, runs: runs.result.runs, today: today()).matches[sessionId]
    }

    private func isWithinAutoWindow(_ sessionId: String) -> Bool {
        guard let session = plans.plan?.session(id: sessionId) else { return false }
        return session.date >= today().adding(days: -AssessmentRules.autoWindowDays)
    }
}
