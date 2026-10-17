import Foundation
import Domain

/// A coach note from a model, with what it cost.
public struct CoachNoteResult: Sendable, Equatable {
    public let note: CoachNote
    public let usage: LLMUsage
    /// The exact prompt sent.
    public let promptText: String
    /// The model that answered (a fallback may differ from the one asked).
    public let model: ModelChoice

    public init(note: CoachNote, usage: LLMUsage, promptText: String, model: ModelChoice) {
        self.note = note
        self.usage = usage
        self.promptText = promptText
        self.model = model
    }
}

/// Writes post-workout notes from a finished prompt (instructions and facts,
/// built by `DetailedNotePromptBuilder`). Adapters throw `LLMError` only, and
/// record every attempt they send (success or failure) through `LLMCallRecorder`
/// under `purpose`.
public protocol CoachingModel: Sendable {
    func writeWorkoutNote(_ prompt: Prompt, model: ModelChoice, purpose: LLMCallPurpose) async throws -> CoachNoteResult
}

/// A plan structure from a model, with what it cost.
public struct PlanDraftResult: Sendable, Equatable {
    public let draft: PlanDraft
    public let usage: LLMUsage
    public let promptText: String

    public init(draft: PlanDraft, usage: LLMUsage, promptText: String) {
        self.draft = draft
        self.usage = usage
        self.promptText = promptText
    }
}

/// Drafts a plan's structure (weeks, phases, weekdays, types, km). Code fills in
/// the rest (`ModelPlanGenerator`). Adapters throw `LLMError` only, and record every
/// attempt they send through `LLMCallRecorder` under `purpose`.
public protocol PlanDraftingModel: Sendable {
    func draftPlan(_ request: PlanRequest, model: ModelChoice, purpose: LLMCallPurpose) async throws -> PlanDraftResult
}

/// Private Cloud Compute's daily request limit.
public struct QuotaStatus: Sendable, Equatable, Codable {
    public enum State: String, Sendable, Equatable, Codable {
        case belowLimit, nearingLimit, limitReached
    }

    public let state: State
    public let resetDate: Date?

    public init(state: State, resetDate: Date?) {
        self.state = state
        self.resetDate = resetDate
    }
}

/// Whether a model can run, and what the runtime says about it.
public struct ModelStatus: Sendable, Equatable {
    public let availability: ModelAvailability
    /// Read at runtime, never hardcoded.
    public let contextSize: Int?
    /// Private Cloud Compute only.
    public let quota: QuotaStatus?
    public let detailText: String

    public init(availability: ModelAvailability, contextSize: Int? = nil, quota: QuotaStatus? = nil, detailText: String? = nil) {
        self.availability = availability
        self.contextSize = contextSize
        self.quota = quota
        self.detailText = detailText ?? availability.message
    }
}

public protocol ModelAvailabilityChecker: Sendable {
    func status(for model: ModelChoice) async -> ModelStatus
}
