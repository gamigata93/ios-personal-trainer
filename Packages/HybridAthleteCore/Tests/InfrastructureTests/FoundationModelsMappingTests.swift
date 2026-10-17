import Foundation
import Testing
import FoundationModels
import Application
import Domain
@testable import Infrastructure

/// The framework-to-domain mappings, with real framework values where they can
/// be constructed (macOS 27 hosts).
@Suite("Foundation Models mapping")
struct FoundationModelsMappingTests {
    private func map(_ error: any Error) -> LLMError { FoundationModelsMapping.llmError(error) }

    @Test func errorsWeCanConstruct() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        typealias PCC = PrivateCloudComputeLanguageModel.Error
        #expect(map(PCC.quotaLimitReached(.init(resetDate: reset, debugDescription: "limit"))) == .quotaLimitReached(resetDate: reset))
        #expect(map(PCC.networkFailure(.init(debugDescription: "offline"))) == .networkUnavailable)
        #expect(map(PCC.serviceUnavailable(.init(debugDescription: "Missing entitlement com.apple.developer"))) == .unavailable(.notEnabledForBuild))
        #expect(map(PCC.serviceUnavailable(.init(debugDescription: "maintenance"))) == .unavailable(.unavailable("maintenance")))

        #expect(map(LanguageModelError.contextSizeExceeded(.init(contextSize: 4_096, tokenCount: 5_000, debugDescription: "too big"))) == .contextTooLarge)
        #expect(map(LanguageModelError.rateLimited(.init(resetDate: reset, debugDescription: "slow down"))) == .quotaLimitReached(resetDate: reset))
        #expect(map(LanguageModelError.guardrailViolation(.init(debugDescription: "unsafe"))) == .guardrailViolation)
        #expect(map(LanguageModelError.refusal(.init(explanation: "no", debugDescription: "refused"))) == .guardrailViolation)
        #expect(map(LanguageModelError.timeout(.init(debugDescription: "slow"))) == .timedOut)
        #expect(map(LanguageModelError.unsupportedGenerationGuide(.init(schemaName: "X", debugDescription: "bad guide"))) == .malformedOutput("bad guide"))
        #expect(map(SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "downloading"))) == .unavailable(.notReady))

    }

    @Test func ourOwnErrorsPassThrough() {
        #expect(map(CancellationError()) == .cancelled)
        #expect(map(LLMError.timedOut) == .timedOut)
        struct Odd: Error {}
        if case .other = map(Odd()) {} else { Issue.record("expected .other") }
    }

    @Test func availability() {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        #expect(FoundationModelsMapping.availability(SystemLanguageModel.Availability.available) == .available)
        #expect(FoundationModelsMapping.availability(SystemLanguageModel.Availability.unavailable(.deviceNotEligible)) == .notEligible)
        #expect(FoundationModelsMapping.availability(SystemLanguageModel.Availability.unavailable(.appleIntelligenceNotEnabled)) == .notReady)
        #expect(FoundationModelsMapping.availability(SystemLanguageModel.Availability.unavailable(.modelNotReady)) == .notReady)
        #expect(FoundationModelsMapping.availability(PrivateCloudComputeLanguageModel.Availability.unavailable(.deviceNotEligible)) == .notEligible)
        #expect(FoundationModelsMapping.availability(PrivateCloudComputeLanguageModel.Availability.unavailable(.systemNotReady)) == .notReady)
        #expect(FoundationModelFactory.reasoningLevel(.moderate) == .moderate)
    }

    @Test func privateCloudWithoutTheEntitlementIsNotEnabled() async {
        let checker = FoundationModelAvailabilityChecker(configuration: .current)
        #expect(await checker.status(for: .privateCloud(reasoning: .moderate)).availability == .notEnabledForBuild)
        await #expect(throws: LLMError.unavailable(.notEnabledForBuild)) {
            try await FoundationModelsCoachingModel().writeWorkoutNote(WorkoutNoteFixture.samplePrompt, model: .privateCloud(reasoning: .light), purpose: .labCoachNote)
        }
    }

    @Test func deadline() async throws {
        await #expect(throws: LLMError.timedOut) {
            try await withDeadline(seconds: 0.05) { try await Task.sleep(for: .seconds(5)); return 1 }
        }
        #expect(try await withDeadline(seconds: 5) { 7 } == 7)
    }
}

@Suite("Fake models and the template")
struct FakeLanguageModelTests {
    private struct TestClock: Clock { func now() -> Date { Date(timeIntervalSince1970: 1_793_178_000) } }

    @Test func expandingTheTemplateStructureReproducesItsSessions() {
        let request = SeedPlan.request
        let template = TemplatePlanGenerator.plan(for: request)
        let draft = PlanDraft(weeks: template.weeks.map { week in
            DraftWeek(index: week.index, phase: week.phase, sessions: week.sessions.map { DraftSession(weekday: $0.date.weekday, type: $0.type, distanceKm: $0.distanceKm) })
        })
        let expanded = PlanDraftExpander.expand(draft, request: request, generatedBy: "template-v1")
        #expect(expanded.sessions == template.sessions)
        #expect(PlanValidator.violations(expanded, request: request).isEmpty)
    }

    @Test func invalidPlanScenarioBreaksOneRuleOnlyWithoutNotes() async throws {
        let fake = FakeLanguageModel(scenario: .invalidPlan, clock: TestClock())
        let first = try await fake.draftPlan(SeedPlan.request, model: .onDevice, purpose: .labPlanDraft)
        #expect(PlanDraftValidator.violations(first.draft, request: SeedPlan.request).count == 1)
        let second = try await fake.draftPlan(SeedPlan.request.revised(notes: ["fix it"]), model: .onDevice, purpose: .labPlanDraft)
        #expect(PlanDraftValidator.violations(second.draft, request: SeedPlan.request).isEmpty)

        // The real flow: two attempts succeed; one attempt fails.
        let generator = ModelPlanGenerator(drafting: fake, model: .onDevice)
        let plan = try await ValidatingPlanGenerator(inner: generator).generate(SeedPlan.request)
        #expect(plan.generatedBy == "on-device-v1")
        await #expect(throws: LLMError.self) { try await ValidatingPlanGenerator(inner: generator, maxAttempts: 1).generate(SeedPlan.request) }
    }

    @Test func failingScenarios() async {
        let clock = TestClock()
        await #expect(throws: LLMError.unavailable(.notReady)) {
            try await FakeLanguageModel(scenario: .unavailable, clock: clock).writeWorkoutNote(WorkoutNoteFixture.samplePrompt, model: .onDevice, purpose: .labCoachNote)
        }
        await #expect(throws: LLMError.quotaLimitReached(resetDate: clock.now().addingTimeInterval(3 * 3_600))) {
            try await FakeLanguageModel(scenario: .quota, clock: clock).draftPlan(SeedPlan.request, model: .onDevice, purpose: .labPlanDraft)
        }
        #expect(await FakeModelAvailabilityChecker(scenario: .unavailable, clock: clock).status(for: .onDevice).availability == .notReady)
        #expect(await FakeModelAvailabilityChecker(scenario: .ok, clock: clock).status(for: .privateCloud(reasoning: .deep)).contextSize == 32_768)
    }
}
