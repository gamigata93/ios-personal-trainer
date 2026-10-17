import Foundation
import Domain

/// What the Model Lab asks a model to do.
public enum ModelExperiment: Sendable, Equatable {
    /// The real note pipeline's facts for one completed session.
    case workoutNote(WorkoutNoteRequest)
    case planDraft(PlanRequest)

    /// "workoutNote" or "planDraft".
    public var name: String {
        switch self {
        case .workoutNote: "workoutNote"
        case .planDraft: "planDraft"
        }
    }

    /// The prompt at full detail (a workout note may be compacted for a small context).
    public var prompt: Prompt {
        switch self {
        case .workoutNote(let request): DetailedNotePromptBuilder.build(FactsBuilder.build(request))
        case .planDraft(let request): PlanPromptBuilder.build(request)
        }
    }
}

/// A plan draft as the Lab shows it.
public struct PlanDraftTable: Sendable, Equatable {
    /// "Wk 3 · base · 22.5 km · Mon tempo 6.0, Wed easy 7.5, Fri long 9.0".
    public let rows: [String]
    /// "Weekly km, model / template: 18.5/18.5, 20.0/20.5, ...".
    public let comparisonLine: String?
    public let draft: PlanDraft
}

public enum ExperimentOutput: Sendable, Equatable {
    case workoutNote(CoachNote)
    case planDraft(PlanDraftTable)
}

/// One run of one experiment on one model.
public struct ExperimentResult: Sendable, Equatable {
    public let experiment: String
    public let model: ModelChoice
    public let status: ModelStatus
    public let output: ExperimentOutput?
    public let usage: LLMUsage?
    /// Rule problems (plan draft): shown, never retried in the Lab.
    public let violations: [String]
    /// The note guard's issues (workout note): any one would reject the note in the real flow.
    public let softFlags: [String]
    public let promptText: String
    public let error: LLMError?
    /// Workout note only: the facts level (0-3) and the estimated prompt tokens.
    public var factsLevel: Int?
    public var estimatedTokens: Int?

    public init(
        experiment: String, model: ModelChoice, status: ModelStatus, output: ExperimentOutput?, usage: LLMUsage?,
        violations: [String], softFlags: [String], promptText: String, error: LLMError?,
        factsLevel: Int? = nil, estimatedTokens: Int? = nil
    ) {
        self.experiment = experiment
        self.model = model
        self.status = status
        self.output = output
        self.usage = usage
        self.violations = violations
        self.softFlags = softFlags
        self.promptText = promptText
        self.error = error
        self.factsLevel = factsLevel
        self.estimatedTokens = estimatedTokens
    }

    /// "Guard passed", "Guard: 2 issues"; nil without a note.
    public var guardText: String? {
        guard case .workoutNote = output else { return nil }
        return softFlags.isEmpty ? "Guard passed" : "Guard: \(softFlags.count) \(softFlags.count == 1 ? "issue" : "issues")"
    }

    /// "Valid", "1 issue", "3 issues"; nil when there is no output.
    public var validityText: String? {
        guard output != nil else { return nil }
        let count = violations.count + softFlags.count
        return count == 0 ? "Valid" : (count == 1 ? "1 issue" : "\(count) issues")
    }
}

/// Runs a Lab experiment on models, one after another (never in parallel), with
/// ONE attempt each so the raw quality shows. Never saves anything.
public struct RunModelExperiment: Sendable {
    private let coaching: any CoachingModel
    private let drafting: any PlanDraftingModel
    private let availability: any ModelAvailabilityChecker
    /// The template, to compare weekly totals with.
    private let template: any PlanGenerator

    public init(
        coaching: any CoachingModel,
        drafting: any PlanDraftingModel,
        availability: any ModelAvailabilityChecker,
        template: any PlanGenerator
    ) {
        self.coaching = coaching
        self.drafting = drafting
        self.availability = availability
        self.template = template
    }

    public func execute(_ experiment: ModelExperiment, models: [ModelChoice]) async -> [ExperimentResult] {
        var results: [ExperimentResult] = []
        for model in models {
            if Task.isCancelled { break }
            results.append(await run(experiment, model: model))
        }
        return results
    }

    /// Every model of `provider` that is available right now ("Run all" never mixes
    /// free and paid models).
    public func availableModels(_ provider: LLMProvider) async -> [ModelChoice] {
        var models: [ModelChoice] = []
        for model in ModelChoice.all where model.provider == provider {
            guard await availability.status(for: model).availability.isAvailable else { continue }
            models.append(model)
        }
        return models
    }

    public func status(for model: ModelChoice) async -> ModelStatus {
        await availability.status(for: model)
    }

    public func run(_ experiment: ModelExperiment, model: ModelChoice) async -> ExperimentResult {
        let status = await availability.status(for: model)
        // A workout note uses the facts level that fits this model, like the real flow.
        var facts: WorkoutFacts?
        if case .workoutNote(let request) = experiment {
            facts = DetailedNotePromptBuilder.fittingFacts(request, contextSize: model == .onDevice ? status.contextSize : nil)
        }
        let promptText = facts.map { DetailedNotePromptBuilder.build($0).fullText } ?? experiment.prompt.fullText
        let level = facts?.level
        let tokens = facts.map(DetailedNotePromptBuilder.estimatedTokens)
        func failure(_ error: LLMError) -> ExperimentResult {
            ExperimentResult(
                experiment: experiment.name, model: model, status: status, output: nil, usage: nil,
                violations: [], softFlags: [], promptText: promptText, error: error, factsLevel: level, estimatedTokens: tokens
            )
        }
        guard status.availability.isAvailable else { return failure(.unavailable(status.availability)) }

        do {
            switch experiment {
            case .workoutNote(let request):
                guard let facts else { return failure(.contextTooLarge) }
                let result = try await coaching.writeWorkoutNote(DetailedNotePromptBuilder.build(facts), model: model, purpose: .labCoachNote)
                let issues = DetailedNoteGuard.issues(result.note, facts: facts.text, runDistanceKm: request.review.doneKm)
                return ExperimentResult(
                    experiment: experiment.name, model: model, status: status, output: .workoutNote(result.note), usage: result.usage,
                    violations: [], softFlags: issues.map(\.message),
                    promptText: result.promptText, error: nil, factsLevel: facts.level, estimatedTokens: tokens
                )
            case .planDraft(let request):
                let result = try await drafting.draftPlan(request, model: model, purpose: .labPlanDraft)
                var violations = PlanDraftValidator.violations(result.draft, request: request).map(\.message)
                if violations.isEmpty {
                    let plan = PlanDraftExpander.expand(result.draft, request: request, generatedBy: model.generatedBy)
                    violations = PlanValidator.violations(plan, request: request).map(\.message)
                }
                let templatePlan = try? await template.generate(request)
                return ExperimentResult(
                    experiment: experiment.name, model: model, status: status,
                    output: .planDraft(Self.table(result.draft, template: templatePlan)), usage: result.usage,
                    violations: violations, softFlags: [], promptText: result.promptText, error: nil
                )
            }
        } catch let error as LLMError {
            return failure(error)
        } catch is CancellationError {
            return failure(.cancelled)
        } catch {
            return failure(.other(String(describing: type(of: error))))
        }
    }

    /// One row per week, plus the weekly totals next to the template's.
    static func table(_ draft: PlanDraft, template: TrainingPlan?) -> PlanDraftTable {
        let rows = draft.weeks.map { week in
            let sessions = week.sessions.sorted { $0.weekday < $1.weekday }
                .map { "\(HomeFormat.shortWeekday($0.weekday)) \($0.type.rawValue) \(SessionFormat.distanceText(km: $0.distanceKm).dropLast(3))" }
                .joined(separator: ", ")
            return "Wk \(week.index) · \(week.phase.rawValue) · \(SessionFormat.distanceText(km: week.totalKm)) · \(sessions)"
        }
        let comparison = template.map { plan in
            let pairs = zip(draft.weeks.map(\.totalKm), plan.weeks.map(\.totalKm)).map { model, template in
                "\(SessionFormat.distanceText(km: model).dropLast(3))/\(SessionFormat.distanceText(km: template).dropLast(3))"
            }
            return "Weekly km, model / template: " + pairs.joined(separator: ", ")
        }
        return PlanDraftTable(rows: rows, comparisonLine: comparison, draft: draft)
    }
}

/// The Lab's plan draft request: the stored race setup when a plan exists,
/// otherwise a fixed 10 km race 8 weeks away on Mon/Wed/Fri; fitness from the
/// cached summaries. Never saves anything.
public struct BuildLabPlanRequest: Sendable {
    public static let sampleWeeks = 8
    public static let sampleDistanceKm = 10.0

    private let fitness: LoadFitnessSummary
    private let clock: any Clock
    private let calendar: Calendar

    public init(fitness: LoadFitnessSummary, clock: any Clock, calendar: Calendar) {
        self.fitness = fitness
        self.clock = clock
        self.calendar = calendar
    }

    /// With a plan, the request it was built from: its race and its start (the
    /// day before the plan start is the "today" that yields that start).
    public func execute(plan: TrainingPlan?) async -> PlanRequest {
        let today = plan.map { $0.planStart.adding(days: -1) } ?? LocalDate(date: clock.now(), calendar: calendar)
        let race = plan?.race ?? RaceSetup(
            distanceKm: Self.sampleDistanceKm,
            elevationGainM: 0,
            // The Sunday of the 8th plan week.
            raceDate: PlanCalendar.planStart(today: today).adding(days: 7 * Self.sampleWeeks - 1),
            trainingDays: [.monday, .wednesday, .friday]
        )
        return PlanRequest(
            race: race,
            fitness: await fitness.execute(),
            today: today,
            planKind: plan?.planKind ?? PlanKind.from(distanceKm: race.distanceKm),
            source: .custom
        )
    }
}
