import Foundation
import Domain

/// Builds a training plan from a request. The template is the first adapter;
/// LLM adapters implement the same port later. Whatever comes back is checked
/// by `PlanValidator` before it is saved, so adapters need not be trusted.
public protocol PlanGenerator: Sendable {
    func generate(_ request: PlanRequest) async throws -> TrainingPlan
}
