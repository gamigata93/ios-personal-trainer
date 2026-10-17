import Foundation
import Observation
import Domain
import Application

/// One pushed session detail, by id, over the shared plan, runs and coach notes.
@MainActor
@Observable
final class SessionDetailViewModel {
    /// The coach's note card.
    enum CoachCard: Equatable {
        /// Not completed: no card.
        case hidden
        case generating
        case waitingForUnlock
        case ready(ReadyNote)
        case write
        case failed
    }

    struct ReadyNote: Equatable {
        let note: CoachNote
        /// "Written by Apple on-device · today 09:12".
        let footer: String
        /// The fallback reason, when a rule-based note stands in.
        let fallbackText: String?
        let isStale: Bool
        /// Headline, parts and source, for VoiceOver.
        let spoken: String
    }

    let sessionID: String

    private let plans: ActivePlanStore
    private let runs: CompletedRunsStore
    private let notes: CoachNoteStore
    private let getSessionDetail: GetSessionDetail
    private let clock: any Clock
    private let calendar: Calendar

    init(
        sessionID: String,
        plans: ActivePlanStore,
        runs: CompletedRunsStore,
        notes: CoachNoteStore,
        getSessionDetail: GetSessionDetail,
        clock: any Clock,
        calendar: Calendar
    ) {
        self.sessionID = sessionID
        self.plans = plans
        self.runs = runs
        self.notes = notes
        self.getSessionDetail = getSessionDetail
        self.clock = clock
        self.calendar = calendar
    }

    /// Nil when the session is no longer in the plan.
    var detail: SessionDetailOverview? {
        plans.plan.flatMap { getSessionDetail.execute(plan: $0, runs: runs.result.runs, sessionID: sessionID) }
    }

    private var isCompleted: Bool { detail?.status == .completed }

    /// Analyzes the run and writes a note when one is due.
    func appear() async {
        guard isCompleted else { return }
        await notes.open(sessionID)
    }

    /// Tiles, splits, zones and plan vs actual: from the analysis, or from the
    /// run's totals until the analysis is ready.
    var breakdown: WorkoutBreakdown? {
        guard isCompleted else { return nil }
        if let prepared = notes.prepared[sessionID] { return WorkoutBreakdown.make(prepared.request.review) }
        guard
            let plan = plans.plan, let session = plan.session(id: sessionID),
            let run = PlanProgress(plan: plan, runs: runs.result.runs, today: LocalDate(date: clock.now(), calendar: calendar)).matches[sessionID]
        else { return nil }
        let review = WorkoutReview(session: session, run: run, analysis: .minimal(run: run, computedAt: clock.now()), profile: nil)
        return WorkoutBreakdown.make(review)
    }

    /// "Unlock your phone to analyze this run." while Health is locked.
    var analysisWaitingText: String? {
        notes.analysisWaiting.contains(sessionID) && notes.prepared[sessionID] == nil ? "Unlock your phone to analyze this run." : nil
    }

    var coachCard: CoachCard {
        guard isCompleted else { return .hidden }
        switch notes.state(for: sessionID) {
        case .idle: return .write
        case .generating: return .generating
        case .waitingForUnlock: return .waitingForUnlock
        case .failed: return .failed
        case .ready(let saved, let stale):
            let footer = "Written by \(saved.writerName) · \(UpdatedLabel.text(now: clock.now(), then: saved.createdAt, calendar: calendar))"
            let fallback = saved.fallback?.message
            let spoken = [
                "Coach's note", saved.note.headline, "How it went: \(saved.note.howItWent)", "Versus the plan: \(saved.note.versusPlan)",
                "The program: \(saved.note.programStatus)", "Next: \(saved.note.nextStep)", footer, fallback,
            ].compactMap { $0 }.joined(separator: ". ")
            return .ready(ReadyNote(note: saved.note, footer: footer, fallbackText: fallback, isStale: stale, spoken: spoken))
        }
    }

    func write() { notes.write(sessionID) }
    func regenerate() { notes.regenerate(sessionID) }

    /// The note as plain text (Copy note).
    var noteText: String? {
        if case .ready(let ready) = coachCard { return ready.note.plainText }
        return nil
    }

    #if DEBUG
    /// The exact prompt text that would be sent (instructions and full facts).
    var factsText: String? {
        notes.prepared[sessionID].map { DetailedNotePromptBuilder.build($0.facts).fullText }
    }

    var analysisJSON: String? {
        notes.prepared[sessionID].flatMap { WorkoutNoteDebugJSON.analysis($0.analysis) }
    }

    var noteJSON: String? {
        notes.notes[sessionID].flatMap(WorkoutNoteDebugJSON.note)
    }
    #endif
}
