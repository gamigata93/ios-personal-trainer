import Foundation
import Domain

/// What the Model Lab asks a model to do.
public enum ModelExperiment: Sendable, Equatable {
    case coachNote(CoachNoteRequest)
    case planDraft(PlanRequest)

    /// "coachNote" or "planDraft".
    public var name: String {
        switch self {
        case .coachNote: "coachNote"
        case .planDraft: "planDraft"
        }
    }

    /// The exact prompt (instructions and request) the model gets.
    public var prompt: Prompt {
        switch self {
        case .coachNote(let request): CoachNotePromptBuilder.build(request)
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
    case coachNote(CoachNote)
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
    /// Soft problems (coach note): too long, numbers not in the facts.
    public let softFlags: [String]
    public let promptText: String
    public let error: LLMError?

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
        let promptText = experiment.prompt.fullText
        func failure(_ error: LLMError) -> ExperimentResult {
            ExperimentResult(
                experiment: experiment.name, model: model, status: status, output: nil, usage: nil,
                violations: [], softFlags: [], promptText: promptText, error: error
            )
        }
        guard status.availability.isAvailable else { return failure(.unavailable(status.availability)) }

        do {
            switch experiment {
            case .coachNote(let request):
                let result = try await coaching.writeWorkoutNote(request, model: model, purpose: .labCoachNote)
                let facts = CoachNotePromptBuilder.factLines(request).joined(separator: "\n")
                return ExperimentResult(
                    experiment: experiment.name, model: model, status: status, output: .coachNote(result.note), usage: result.usage,
                    violations: [], softFlags: CoachNoteValidator.flags(result.note, facts: facts).map(\.message),
                    promptText: result.promptText, error: nil
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

/// The facts for the newest session that a run completed, with last night's
/// recovery when it is known. Summaries only.
public struct BuildLatestSessionFacts: Sendable {
    public init() {}

    public func execute(
        plan: TrainingPlan,
        runs: [CompletedRun],
        today: LocalDate,
        sleepNights: [SleepNight] = [],
        hrvNights: [HRVNight] = [],
        restingDays: [RestingHRDay] = []
    ) -> CoachNoteRequest? {
        let progress = PlanProgress(plan: plan, runs: runs, today: today)
        guard
            let session = plan.sessions.filter({ $0.date <= today && progress.matches[$0.id] != nil }).max(by: { $0.date < $1.date }),
            let run = progress.matches[session.id],
            let week = plan.weeks.first(where: { $0.sessions.contains { $0.id == session.id } })
        else { return nil }
        return CoachNoteRequest(
            sessionName: session.name,
            sessionType: session.type,
            status: progress.status(of: session),
            plannedKm: session.distanceKm,
            doneKm: run.distanceKm,
            doneDurationSeconds: run.durationSeconds,
            paceSecPerKm: run.distanceKm > 0 ? Int((run.durationSeconds / run.distanceKm).rounded()) : nil,
            weekIndex: week.index,
            weeksTotal: plan.weeks.count,
            phase: week.phase,
            daysToRace: max(0, session.date.days(to: plan.race.raceDate)),
            sleep: sleepFact(sleepNights, today: today),
            hrv: hrvFact(hrvNights, today: today),
            restingHr: restingFact(restingDays, today: today)
        )
    }

    private func sleepFact(_ nights: [SleepNight], today: LocalDate) -> SleepFact? {
        guard case .shown(let night, _) = SleepSelection.select(nights: nights, today: today) else { return nil }
        let comparison = SleepComparison.make(shown: night, nights: nights)
        return SleepFact(
            asleepMinutes: night.asleepMinutes,
            deltaPercent: comparison?.deltaPercent,
            nightsUsed: comparison?.nightsUsed ?? SleepRules.baselineNights
        )
    }

    private func hrvFact(_ nights: [HRVNight], today: LocalDate) -> HRVFact? {
        guard case .shown(let night, _) = RecentSelection.select(
            nights, date: \.wakeDate, today: today, maxAgeDays: RecoveryRules.maxAgeDays, label: RecoveryLabel.night
        ) else { return nil }
        let previous = MetricComparison.previous(nights, date: \.wakeDate, before: night.wakeDate, days: RecoveryRules.baselineWindow)
        let comparison = MetricComparison.make(
            shown: night.meanMs, previous: previous.map(\.meanMs), mode: .percent,
            neutralBand: RecoveryRules.hrvNeutralPercent, direction: .higherIsBetter, minValues: RecoveryRules.minBaselineValues
        )
        return HRVFact(valueMs: night.meanMs, deltaPercent: comparison?.delta, nightsUsed: comparison?.countUsed ?? RecoveryRules.baselineWindow)
    }

    private func restingFact(_ days: [RestingHRDay], today: LocalDate) -> RestingHRFact? {
        guard case .shown(let day, _) = RecentSelection.select(
            days, date: \.date, today: today, maxAgeDays: RecoveryRules.maxAgeDays, label: RecoveryLabel.day
        ) else { return nil }
        let previous = MetricComparison.previous(days, date: \.date, before: day.date, days: RecoveryRules.baselineWindow)
        let comparison = MetricComparison.make(
            shown: day.bpm, previous: previous.map(\.bpm), mode: .absolute,
            neutralBand: RecoveryRules.restingHRNeutralBpm, direction: .lowerIsBetter, minValues: RecoveryRules.minBaselineValues
        )
        return RestingHRFact(bpm: day.bpm, deltaBpm: comparison?.delta, daysUsed: comparison?.countUsed ?? RecoveryRules.baselineWindow)
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
