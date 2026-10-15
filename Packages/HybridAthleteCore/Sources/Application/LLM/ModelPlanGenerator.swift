import Foundation
import Domain

/// A plan from a model: the model drafts the structure, the draft's shape is
/// checked (`PlanDraftValidator`), and code expands it (`PlanDraftExpander`).
/// A bad shape throws `LLMError.malformedOutput` with the messages, one per line.
public struct ModelPlanGenerator: PlanGenerator {
    private let drafting: any PlanDraftingModel
    private let model: ModelChoice

    public init(drafting: any PlanDraftingModel, model: ModelChoice) {
        self.drafting = drafting
        self.model = model
    }

    public func generate(_ request: PlanRequest) async throws -> TrainingPlan {
        let result = try await drafting.draftPlan(request, model: model, purpose: .planGeneration)
        let violations = PlanDraftValidator.violations(result.draft, request: request)
        guard violations.isEmpty else {
            throw LLMError.malformedOutput(violations.map(\.message).joined(separator: "\n"))
        }
        return PlanDraftExpander.expand(result.draft, request: request, generatedBy: model.generatedBy)
    }
}

/// Checks a generator's plan with `PlanValidator` and asks again with the
/// problems as revision notes. Only rule problems are retried (violations and
/// malformed output); unavailable, quota, network, guardrail, timeout and
/// cancellation propagate at once. After the last attempt it throws
/// `LLMError.invalidPlan` with the last messages.
public struct ValidatingPlanGenerator: PlanGenerator {
    public static let defaultAttempts = 2

    private let inner: any PlanGenerator
    public let maxAttempts: Int

    public init(inner: any PlanGenerator, maxAttempts: Int = ValidatingPlanGenerator.defaultAttempts) {
        self.inner = inner
        self.maxAttempts = max(1, maxAttempts)
    }

    public func generate(_ request: PlanRequest) async throws -> TrainingPlan {
        var attemptRequest = request
        var messages: [String] = []
        for _ in 0..<maxAttempts {
            do {
                let plan = try await inner.generate(attemptRequest)
                messages = PlanValidator.violations(plan, request: request).map(\.message)
                if messages.isEmpty { return plan }
            } catch LLMError.malformedOutput(let text) {
                messages = text.split(separator: "\n").map(String.init)
            }
            attemptRequest = request.revised(notes: Array(messages.prefix(PlanPromptBuilder.maxRevisionNotes)))
        }
        throw LLMError.invalidPlan(messages)
    }
}

/// Falls back on any `LLMError` except cancellation. The plan's generatedBy
/// tells which generator produced it.
public struct FallbackPlanGenerator: PlanGenerator {
    private let primary: any PlanGenerator
    private let fallback: any PlanGenerator

    public init(primary: any PlanGenerator, fallback: any PlanGenerator) {
        self.primary = primary
        self.fallback = fallback
    }

    public func generate(_ request: PlanRequest) async throws -> TrainingPlan {
        do {
            return try await primary.generate(request)
        } catch let error as LLMError where error != .cancelled {
            return try await fallback.generate(request)
        }
    }
}

/// Retries a failed Private Cloud Compute note on the on-device model, on any
/// `LLMError` except cancellation. Other models' failures (on-device, Claude)
/// surface as they are. The result names the model that answered.
public struct FallbackCoachingModel: CoachingModel {
    private let primary: any CoachingModel
    private let fallback: any CoachingModel
    private let fallbackModel: ModelChoice

    public init(primary: any CoachingModel, fallback: any CoachingModel, fallbackModel: ModelChoice = .onDevice) {
        self.primary = primary
        self.fallback = fallback
        self.fallbackModel = fallbackModel
    }

    public func writeWorkoutNote(_ request: CoachNoteRequest, model: ModelChoice, purpose: LLMCallPurpose) async throws -> CoachNoteResult {
        do {
            return try await primary.writeWorkoutNote(request, model: model, purpose: purpose)
        } catch let error as LLMError where error != .cancelled && model.isPrivateCloud && model != fallbackModel {
            return try await fallback.writeWorkoutNote(request, model: fallbackModel, purpose: purpose)
        }
    }
}

#if DEBUG
/// DEBUG `-planDelay <seconds>`: waits before generating, to see the Generating
/// screen with the instant template. Off unless asked for.
public struct SimulatedDelayPlanGenerator: PlanGenerator {
    private let inner: any PlanGenerator
    public let seconds: Double

    public init(inner: any PlanGenerator, seconds: Double) {
        self.inner = inner
        self.seconds = seconds
    }

    public func generate(_ request: PlanRequest) async throws -> TrainingPlan {
        try await Task.sleep(for: .seconds(seconds))
        return try await inner.generate(request)
    }
}
#endif
