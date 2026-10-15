#if DEBUG
import Foundation
import Domain

/// DEBUG only: one Lab result as pretty JSON for "Copy result JSON":
/// experiment, model, availability, contextSize, latencyMs, usage (with the
/// estimated cost for Claude), output, violations, softFlags, promptText, error.
/// Never the API key.
public enum ExperimentResultJSON {
    public static func string(_ result: ExperimentResult, errorText: LLMErrorText) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let payload = Payload(
            experiment: result.experiment,
            model: result.model.id,
            availability: result.status.availability.chipText,
            contextSize: result.status.contextSize,
            latencyMs: result.usage?.latencyMs,
            usage: result.usage.map {
                Usage(
                    input: $0.inputTokens, cachedInput: $0.cachedInputTokens, cacheWrite: $0.cacheWriteTokens,
                    output: $0.outputTokens, reasoning: $0.reasoningTokens, costMicros: $0.costMicros
                )
            },
            output: result.output.map(Output.init),
            violations: result.violations,
            softFlags: result.softFlags,
            promptText: result.promptText,
            error: result.error.map(errorText.message)
        )
        return (try? encoder.encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private struct Payload: Encodable {
        let experiment: String
        let model: String
        let availability: String
        let contextSize: Int?
        let latencyMs: Int?
        let usage: Usage?
        let output: Output?
        let violations: [String]
        let softFlags: [String]
        let promptText: String
        let error: String?
    }

    private struct Usage: Encodable {
        let input: Int?
        let cachedInput: Int?
        let cacheWrite: Int?
        let output: Int?
        let reasoning: Int?
        /// Claude only: estimated from the price table.
        let costMicros: Int64?
    }

    private struct Output: Encodable {
        let coachNote: CoachNote?
        let planDraft: PlanDraft?
        let rows: [String]?

        init(_ output: ExperimentOutput) {
            switch output {
            case .coachNote(let note):
                coachNote = note
                planDraft = nil
                rows = nil
            case .planDraft(let table):
                coachNote = nil
                planDraft = table.draft
                rows = table.rows
            }
        }
    }
}
#endif
