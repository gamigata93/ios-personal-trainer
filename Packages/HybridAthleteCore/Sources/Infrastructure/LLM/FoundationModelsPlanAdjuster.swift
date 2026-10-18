import Foundation
import FoundationModels
import Application
import Domain

/// Suggested schedules through guided generation, from Apple's models or Claude:
/// the prompt (`AdjustmentPromptBuilder`) in, an `AdjustmentDraft` out.
/// Validation and expansion happen in `SuggestPlanAdjustment`. Every attempt
/// sent is recorded. Prompts and answers are never logged.
public struct FoundationModelsPlanAdjuster: PlanAdjustingModel {
    private let runner: ModelCallRunner

    public init(configuration: FoundationModelsConfiguration = .current, secrets: (any SecretStore)? = nil, meter: LLMCallMeter? = nil) {
        runner = ModelCallRunner(factory: FoundationModelFactory(configuration: configuration, secrets: secrets), meter: meter)
    }

    public func adjustPlan(_ prompt: Domain.Prompt, model choice: ModelChoice, purpose: LLMCallPurpose) async throws -> AdjustmentDraftResult {
        let options = FoundationModelFactory.generationOptions(for: choice, task: purpose.task)
        let contextOptions = FoundationModelFactory.contextOptions(for: choice)
        let answer = try await runner.run(
            choice,
            purpose: purpose,
            instructions: prompt.instructions,
            timeoutSeconds: FoundationModelsLimits.planDraftTimeoutSeconds
        ) { session in
            let response = try await session.respond(
                to: prompt.text, generating: AdjustmentDTO.self, options: options, contextOptions: contextOptions
            )
            return (try response.content.draft(), response.usage)
        }
        return AdjustmentDraftResult(draft: answer.value, usage: answer.usage, promptText: prompt.fullText)
    }
}

@Generable(description: "The new schedule for the days that may change")
struct AdjustmentDTO {
    @Guide(description: "Every run on those days")
    var runs: [AdjustedRunDTO]
    @Guide(description: "Every strength session on those days, one per day at most")
    var strength: [AdjustedStrengthDTO]
    @Guide(description: "One sentence for the athlete, at most 160 characters")
    var reason: String

    func draft() throws -> AdjustmentDraft {
        AdjustmentDraft(runs: try runs.map { try $0.run() }, strength: try strength.map { try $0.strength() }, reason: reason)
    }
}

@Generable(description: "One run")
struct AdjustedRunDTO {
    @Guide(description: "The date as YYYY-MM-DD")
    var date: String
    @Guide(description: "The run type", .anyOf(SessionType.allCases.map(\.rawValue)))
    var type: String
    @Guide(description: "The distance in km, one decimal")
    var distanceKm: Double

    func run() throws -> AdjustmentDraft.Run {
        guard let day = LocalDate(date) else { throw LLMError.malformedOutput("Unknown date \"\(date)\".") }
        guard let kind = SessionType(rawValue: type) else { throw LLMError.malformedOutput("Unknown run type \"\(type)\".") }
        return AdjustmentDraft.Run(date: day, type: kind, distanceKm: distanceKm)
    }
}

@Generable(description: "One strength session")
struct AdjustedStrengthDTO {
    @Guide(description: "The date as YYYY-MM-DD")
    var date: String
    @Guide(description: "What the session trains", .anyOf(StrengthFocus.allCases.map(\.promptName)))
    var focus: String
    @Guide(description: "The session length in minutes, 15 to 60")
    var minutes: Int

    func strength() throws -> AdjustmentDraft.Strength {
        guard let day = LocalDate(date) else { throw LLMError.malformedOutput("Unknown date \"\(date)\".") }
        guard let kind = StrengthFocus(promptName: focus) else { throw LLMError.malformedOutput("Unknown strength focus \"\(focus)\".") }
        return AdjustmentDraft.Strength(date: day, focus: kind, minutes: minutes)
    }
}
