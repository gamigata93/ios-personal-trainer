import Foundation
import FoundationModels
import Application
import Domain

/// Plan structures through guided generation, from Apple's models or Claude:
/// the prompt (`PlanPromptBuilder`) in, a `PlanDraft` out. Validation and
/// expansion happen in `ModelPlanGenerator`. Every attempt sent is recorded.
/// Prompts and answers are never logged.
public struct FoundationModelsPlanDrafter: PlanDraftingModel {
    private let runner: ModelCallRunner

    public init(configuration: FoundationModelsConfiguration = .current, secrets: (any SecretStore)? = nil, meter: LLMCallMeter? = nil) {
        runner = ModelCallRunner(factory: FoundationModelFactory(configuration: configuration, secrets: secrets), meter: meter)
    }

    public func draftPlan(_ request: PlanRequest, model choice: ModelChoice, purpose: LLMCallPurpose) async throws -> PlanDraftResult {
        let prompt = PlanPromptBuilder.build(request)
        let options = FoundationModelFactory.generationOptions(for: choice, task: purpose.task)
        let contextOptions = FoundationModelFactory.contextOptions(for: choice)
        let answer = try await runner.run(
            choice,
            purpose: purpose,
            instructions: prompt.instructions,
            timeoutSeconds: FoundationModelsLimits.planDraftTimeoutSeconds,
            prepare: { model in
                if let system = model as? SystemLanguageModel { try await Self.checkFits(prompt, in: system) }
            }
        ) { session in
            let response = try await session.respond(
                to: prompt.text, generating: PlanDraftDTO.self, options: options, contextOptions: contextOptions
            )
            return (try response.content.draft(), response.usage)
        }
        return PlanDraftResult(draft: answer.value, usage: answer.usage, promptText: prompt.fullText)
    }

    /// Instructions, prompt and schema must leave room for the answer in the
    /// runtime context size (never hardcoded).
    private static func checkFits(_ prompt: Domain.Prompt, in model: SystemLanguageModel) async throws {
        let needed = try await model.tokenCount(for: Instructions(prompt.instructions))
            + model.tokenCount(for: prompt.text)
            + model.tokenCount(for: PlanDraftDTO.generationSchema)
            + FoundationModelsLimits.planDraftOutputReserveTokens
        if needed > model.contextSize { throw LLMError.contextTooLarge }
    }
}

@Generable(description: "The structure of a running training plan")
struct PlanDraftDTO {
    @Guide(description: "Every week of the plan, in order")
    var weeks: [WeekDTO]

    func draft() throws -> PlanDraft {
        PlanDraft(weeks: try weeks.map { try $0.week() })
    }
}

@Generable(description: "One week of the plan")
struct WeekDTO {
    @Guide(description: "The week number, starting at 1")
    var index: Int
    @Guide(description: "The phase of this week", .anyOf(PlanPhase.allCases.map(\.rawValue)))
    var phase: String
    @Guide(description: "The week's sessions, one per training day at most")
    var sessions: [SessionDTO]

    func week() throws -> DraftWeek {
        guard let phase = PlanPhase(rawValue: phase) else { throw LLMError.malformedOutput("Unknown phase \"\(self.phase)\".") }
        return DraftWeek(index: index, phase: phase, sessions: try sessions.map { try $0.session() })
    }
}

@Generable(description: "One run")
struct SessionDTO {
    @Guide(description: "The day of the week", .anyOf(Weekday.allCases.map(\.name)))
    var weekday: String
    @Guide(description: "The session type", .anyOf(SessionType.allCases.map(\.rawValue)))
    var type: String
    @Guide(description: "The distance in km, one decimal")
    var distanceKm: Double

    func session() throws -> DraftSession {
        guard let day = Weekday.allCases.first(where: { $0.name == weekday }) else { throw LLMError.malformedOutput("Unknown weekday \"\(weekday)\".") }
        guard let kind = SessionType(rawValue: type) else { throw LLMError.malformedOutput("Unknown session type \"\(type)\".") }
        return DraftSession(weekday: day, type: kind, distanceKm: distanceKm)
    }
}
