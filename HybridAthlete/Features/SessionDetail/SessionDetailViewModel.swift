import Foundation
import Observation
import Domain
import Application

/// One pushed session detail, by id, over the shared plan and runs.
@MainActor
@Observable
final class SessionDetailViewModel {
    let sessionID: String

    private let plans: ActivePlanStore
    private let runs: CompletedRunsStore
    private let getSessionDetail: GetSessionDetail

    init(sessionID: String, plans: ActivePlanStore, runs: CompletedRunsStore, getSessionDetail: GetSessionDetail) {
        self.sessionID = sessionID
        self.plans = plans
        self.runs = runs
        self.getSessionDetail = getSessionDetail
    }

    /// Nil when the session is no longer in the plan.
    var detail: SessionDetailOverview? {
        plans.plan.flatMap { getSessionDetail.execute(plan: $0, runs: runs.result.runs, sessionID: sessionID) }
    }
}
