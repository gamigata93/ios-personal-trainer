import Foundation
import FoundationModels
import Application
import Domain

/// Coach notes through guided generation, from Apple's on-device or Private
/// Cloud Compute model or from Claude (all behind `LanguageModel`). One session
/// per call; every attempt sent is recorded. Prompts and answers are never logged.
public struct FoundationModelsCoachingModel: CoachingModel {
    private let runner: ModelCallRunner

    public init(configuration: FoundationModelsConfiguration = .current, secrets: (any SecretStore)? = nil, meter: LLMCallMeter? = nil) {
        runner = ModelCallRunner(factory: FoundationModelFactory(configuration: configuration, secrets: secrets), meter: meter)
    }

    public func writeWorkoutNote(_ request: CoachNoteRequest, model choice: ModelChoice, purpose: LLMCallPurpose) async throws -> CoachNoteResult {
        let prompt = CoachNotePromptBuilder.build(request)
        let options = FoundationModelFactory.generationOptions(for: choice, task: purpose.task)
        let contextOptions = FoundationModelFactory.contextOptions(for: choice)
        let answer = try await runner.run(
            choice,
            purpose: purpose,
            instructions: prompt.instructions,
            timeoutSeconds: FoundationModelsLimits.coachNoteTimeoutSeconds
        ) { session in
            let response = try await session.respond(
                to: prompt.text, generating: CoachNoteDTO.self, options: options, contextOptions: contextOptions
            )
            return (response.content.note, response.usage)
        }
        return CoachNoteResult(note: answer.value, usage: answer.usage, promptText: prompt.fullText, model: choice)
    }
}

@Generable(description: "A short coach note about one training session")
struct CoachNoteDTO {
    @Guide(description: "A headline of at most 60 characters")
    var headline: String
    @Guide(description: "What happened, using only the facts, at most 240 characters")
    var observation: String
    @Guide(description: "Exactly one concrete next step, at most 160 characters")
    var nextStep: String

    var note: CoachNote {
        CoachNote(headline: headline, observation: observation, nextStep: nextStep)
    }
}
