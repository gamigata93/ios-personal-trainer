import Foundation
import Observation
import Domain
import Application

/// Builds the plan once, then moves on. No fake delays or progress.
@MainActor
@Observable
final class GeneratingViewModel {
    enum Phase: Equatable {
        case working
        case failed(String)
    }

    let title = "Building your plan"
    let subtitle = "Fitting your training days around race day."

    private(set) var phase: Phase = .working

    private let setup: RaceSetup
    private let source: PlanSource
    private let createPlan: CreatePlan
    private let onSuccess: @MainActor (TrainingPlan) -> Void
    private let onBack: @MainActor () -> Void
    private let errorText: LLMErrorText?
    private var hasStarted = false

    init(
        setup: RaceSetup,
        source: PlanSource,
        createPlan: CreatePlan,
        onSuccess: @escaping @MainActor (TrainingPlan) -> Void,
        onBack: @escaping @MainActor () -> Void,
        errorText: LLMErrorText? = nil
    ) {
        self.errorText = errorText
        self.setup = setup
        self.source = source
        self.createPlan = createPlan
        self.onSuccess = onSuccess
        self.onBack = onBack
    }

    /// Runs once when the screen appears.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await run()
    }

    func retry() async {
        await run()
    }

    func backToSetup() {
        onBack()
    }

    private func run() async {
        phase = .working
        do throws(PlanCreationError) {
            let plan = try await createPlan.execute(setup, source: source)
            onSuccess(plan)
        } catch {
            phase = .failed(Self.message(error, errorText: errorText))
        }
    }

    /// Model failures read through `LLMErrorText` (quota, availability, broken plan).
    static func message(_ error: PlanCreationError, errorText: LLMErrorText? = nil) -> String {
        switch error {
        case .modelFailed(let failure):
            errorText?.message(failure) ?? "Your plan couldn't be built. Try again."
        case .invalidSetup(let issues):
            issues.first?.message ?? "Some race details need a change."
        case .generationFailed:
            "Your plan couldn't be built. Try again."
        case .invalidPlan:
            "The plan didn't pass our safety checks, so nothing was saved. Try again or change your setup."
        case .saveFailed:
            "Your plan was built but couldn't be saved. Try again."
        }
    }
}
