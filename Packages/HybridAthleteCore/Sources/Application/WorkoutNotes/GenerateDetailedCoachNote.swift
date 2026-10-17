import Foundation
import Domain

/// One completed session made ready for a note: its run, analysis, request,
/// full facts and input hash.
public struct PreparedWorkoutNote: Sendable, Equatable {
    public let planId: String
    public let session: PlannedSession
    public let run: CompletedRun
    public let request: WorkoutNoteRequest
    /// Level 0.
    public let facts: WorkoutFacts
    /// SHA-256 of the facts without the program and recovery lines.
    public let inputHash: String

    public var analysis: WorkoutAnalysis { request.review.analysis }
}

public enum PrepareResult: Sendable, Equatable {
    case ready(PreparedWorkoutNote)
    /// Health is locked and the workout has no cached analysis yet.
    case waitingForUnlock
    /// Not completed (or no longer in the plan): never a note.
    case notCompleted
}

/// Analyzes a completed session's run and builds its facts. A not-recorded or
/// missed session never gets facts.
public struct PrepareWorkoutNote: Sendable {
    private let analyze: AnalyzeWorkout
    private let build: BuildWorkoutNoteRequest

    public init(analyze: AnalyzeWorkout, build: BuildWorkoutNoteRequest) {
        self.analyze = analyze
        self.build = build
    }

    /// `cachedOnly` never reads Health (an uncached run is then `waitingForUnlock`).
    public func execute(plan: TrainingPlan, runs: [CompletedRun], sessionId: String, cachedOnly: Bool = false) async throws -> PrepareResult {
        let progress = PlanProgress(plan: plan, runs: runs, today: build.today)
        guard let session = plan.session(id: sessionId), let run = progress.matches[session.id] else { return .notCompleted }
        let analysis: WorkoutAnalysis
        if cachedOnly {
            guard let cached = await analyze.cached(runId: run.id) else { return .waitingForUnlock }
            analysis = cached
        } else {
            switch try await analyze.execute(run: run) {
            case .ready(let ready): analysis = ready
            case .waitingForUnlock: return .waitingForUnlock
            }
        }
        let request = await build.execute(plan: plan, runs: runs, session: session, run: run, analysis: analysis)
        let facts = FactsBuilder.build(request)
        return .ready(PreparedWorkoutNote(
            planId: plan.id, session: session, run: run, request: request, facts: facts,
            inputHash: SHA256Digest.hex(facts.hashText)
        ))
    }
}

/// A note with who wrote it.
public struct WrittenNote: Sendable, Equatable {
    public let note: CoachNote
    public let source: CoachNoteSource
    public let model: ModelChoice?
    public let factsLevel: Int?
    public let fallback: CoachNoteFallback?
}

/// The provider chain: [the preferred model] -> one retry with the guard's
/// issues as revision notes -> the rule-based note. Automatic tries Private
/// Cloud Compute, then on-device, when available. Any `LLMError` goes straight to
/// the rules (with the reason shown); cancellation propagates. Claude goes
/// through the same gated coaching model as the Lab (consent, key, spend caps,
/// ledger), and every attempt is recorded by the adapter with purpose workoutNote.
public struct WriteWorkoutNote: Sendable {
    private let coaching: any CoachingModel
    private let availability: any ModelAvailabilityChecker
    private let settings: any LabSettingsStore
    private let preferenceOverride: CoachModelPreference?

    public init(
        coaching: any CoachingModel,
        availability: any ModelAvailabilityChecker,
        settings: any LabSettingsStore,
        preferenceOverride: CoachModelPreference? = nil
    ) {
        self.coaching = coaching
        self.availability = availability
        self.settings = settings
        self.preferenceOverride = preferenceOverride
    }

    public func preference() async -> CoachModelPreference {
        if let preferenceOverride { return preferenceOverride }
        return await settings.load().coachModelPreference
    }

    public func execute(_ request: WorkoutNoteRequest) async throws -> WrittenNote {
        func rules(_ fallback: CoachNoteFallback?) -> WrittenNote {
            WrittenNote(note: TemplateDetailedNoteWriter.write(request), source: .rules, model: nil, factsLevel: nil, fallback: fallback)
        }

        let chosen: (model: ModelChoice, status: ModelStatus)
        switch await preference() {
        case .ruleBased:
            return rules(nil)
        case .automatic:
            var found: (ModelChoice, ModelStatus)?
            for model in CoachModelPreference.automatic.candidates {
                let status = await availability.status(for: model)
                if status.availability.isAvailable {
                    found = (model, status)
                    break
                }
            }
            guard let found else { return rules(nil) }
            chosen = found
        case .model(let model):
            let status = await availability.status(for: model)
            guard status.availability.isAvailable else {
                return rules(status.availability == .needsAPIKey ? .claudeNotSetUp : .modelUnavailable)
            }
            chosen = (model, status)
        }

        // On-device reports its context size at runtime; other models use the default.
        let contextSize = chosen.model == .onDevice ? chosen.status.contextSize : nil
        guard let facts = DetailedNotePromptBuilder.fittingFacts(request, contextSize: contextSize) else {
            return rules(.modelUnavailable)
        }
        var revisionNotes: [String] = []
        for _ in 0..<2 {
            let result: CoachNoteResult
            do {
                result = try await coaching.writeWorkoutNote(
                    DetailedNotePromptBuilder.build(facts, revisionNotes: revisionNotes), model: chosen.model, purpose: .workoutNote
                )
            } catch let error as LLMError {
                if error == .cancelled { throw CancellationError() }
                return rules(Self.fallback(for: error))
            }
            try Task.checkCancellation()
            let issues = DetailedNoteGuard.issues(result.note, facts: facts.text, runDistanceKm: request.review.doneKm)
            if issues.isEmpty {
                return WrittenNote(note: result.note, source: .model, model: result.model, factsLevel: facts.level, fallback: nil)
            }
            revisionNotes = issues.map(\.message)
        }
        return rules(.guardRejected)
    }

    /// The reason shown with the rule-based note.
    static func fallback(for error: LLMError) -> CoachNoteFallback {
        switch error {
        case .unavailable(.needsAPIKey), .authenticationFailed: .claudeNotSetUp
        case .spendLimit(let text): text == SpendGate.consentText ? .claudeNotSetUp : .spendLimit
        default: .modelUnavailable
        }
    }
}

public enum CoachNoteOutcome: Sendable, Equatable {
    case note(SavedCoachNote)
    case waitingForUnlock
    case notCompleted
}

/// The note for one completed session: the stored one when it is current (and
/// not forced), otherwise a new one written and saved, replacing the old.
/// Cancellation propagates and saves nothing.
public struct GenerateDetailedCoachNote: Sendable {
    private let prepare: PrepareWorkoutNote
    private let write: WriteWorkoutNote
    private let notes: any CoachNoteRepository
    private let clock: any Clock

    public init(prepare: PrepareWorkoutNote, write: WriteWorkoutNote, notes: any CoachNoteRepository, clock: any Clock) {
        self.prepare = prepare
        self.write = write
        self.notes = notes
        self.clock = clock
    }

    public func execute(plan: TrainingPlan, runs: [CompletedRun], sessionId: String, force: Bool) async throws -> CoachNoteOutcome {
        let prepared: PreparedWorkoutNote
        switch try await prepare.execute(plan: plan, runs: runs, sessionId: sessionId) {
        case .ready(let ready): prepared = ready
        case .waitingForUnlock: return .waitingForUnlock
        case .notCompleted: return .notCompleted
        }
        if !force, let stored = try? await notes.note(planId: plan.id, sessionId: sessionId),
           !stored.isStale(runId: prepared.run.id, inputHash: prepared.inputHash) {
            return .note(stored)
        }
        let written = try await write.execute(prepared.request)
        try Task.checkCancellation()
        let saved = SavedCoachNote(
            planId: plan.id,
            sessionId: sessionId,
            runId: prepared.run.id,
            createdAt: clock.now(),
            source: written.source,
            provider: written.model?.provider,
            modelTag: written.model?.id ?? SavedCoachNote.rulesTag,
            note: written.note,
            verdict: prepared.request.review.verdict,
            flags: written.fallback.map { [$0.flag] } ?? [],
            inputHash: prepared.inputHash,
            factsLevel: written.factsLevel
        )
        try await notes.save(saved)
        return .note(saved)
    }
}

/// The stored notes and whether each is still current, without generating.
public struct LoadCoachNotes: Sendable {
    private let notes: any CoachNoteRepository

    public init(notes: any CoachNoteRepository) {
        self.notes = notes
    }

    /// Every stored note of the plan, by session id.
    public func execute(planId: String) async -> [String: SavedCoachNote] {
        let all = (try? await notes.notes(planId: planId)) ?? []
        return Dictionary(all.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
