import Foundation
import FoundationModels
import Application
import Domain

/// "Test" in the Lab: "Reply with OK." on Haiku 5.5 with output capped at 8
/// tokens, through the saved key. Recorded with purpose keyTest. The answer
/// itself is ignored: getting one means the key works.
public struct ClaudeKeyTester: AnthropicKeyTesting {
    private let runner: ModelCallRunner

    public init(secrets: any SecretStore, meter: LLMCallMeter?) {
        runner = ModelCallRunner(factory: FoundationModelFactory(configuration: .current, secrets: secrets), meter: meter)
    }

    public func testKey() async throws -> KeyTestResult {
        let model = ModelChoice.anthropic(LLMSpendRules.keyTestModel)
        let options = FoundationModelFactory.generationOptions(for: model, task: .keyTest)
        let contextOptions = FoundationModelFactory.contextOptions(for: model)
        let answer = try await runner.run(
            model,
            purpose: .keyTest,
            instructions: nil,
            timeoutSeconds: FoundationModelsLimits.keyTestTimeoutSeconds
        ) { session in
            let response = try await session.respond(to: LLMSpendRules.keyTestPrompt, options: options, contextOptions: contextOptions)
            return (true, response.usage)
        }
        return KeyTestResult(latencyMs: answer.usage.latencyMs, costMicros: answer.usage.costMicros)
    }
}
