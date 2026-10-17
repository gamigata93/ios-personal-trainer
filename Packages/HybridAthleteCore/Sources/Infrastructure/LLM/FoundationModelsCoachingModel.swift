import Foundation
import FoundationModels
import Application
import Domain

/// Post-workout notes through guided generation, from a finished prompt, from Apple's on-device or Private
/// Cloud Compute model or from Claude (all behind `LanguageModel`). One session
/// per call; every attempt sent is recorded. Prompts and answers are never logged.
public struct FoundationModelsCoachingModel: CoachingModel {
    private let runner: ModelCallRunner

    public init(configuration: FoundationModelsConfiguration = .current, secrets: (any SecretStore)? = nil, meter: LLMCallMeter? = nil) {
        runner = ModelCallRunner(factory: FoundationModelFactory(configuration: configuration, secrets: secrets), meter: meter)
    }

    public func writeWorkoutNote(_ prompt: Domain.Prompt, model choice: ModelChoice, purpose: LLMCallPurpose) async throws -> CoachNoteResult {
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

@Generable(description: "A post-workout note for one run, in four short parts and a headline")
struct CoachNoteDTO {
    @Guide(description: "A headline of at most 60 characters")
    var headline: String
    @Guide(description: "How the run went, using only the facts, at most 320 characters")
    var howItWent: String
    @Guide(description: "The actual blocks against the planned blocks, at most 320 characters")
    var versusPlan: String
    @Guide(description: "Whether the athlete is following the program, at most 280 characters")
    var programStatus: String
    @Guide(description: "Exactly one concrete next step, at most 200 characters")
    var nextStep: String

    var note: CoachNote {
        CoachNote(headline: headline, howItWent: howItWent, versusPlan: versusPlan, programStatus: programStatus, nextStep: nextStep)
    }
}
