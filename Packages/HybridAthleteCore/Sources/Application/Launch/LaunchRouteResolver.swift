import Foundation
import Domain

/// The first screen after launch.
public enum LaunchRoute: Sendable, Equatable {
    /// Health access has never been requested.
    case connectHealth
    /// Requested, but no plan yet.
    case startingPoint
    /// A plan exists.
    case home
}

/// Picks the launch route from two facts: whether Health access was ever
/// requested, and whether a plan exists.
public struct LaunchRouteResolver: Sendable {
    private let health: any HealthDataSource
    private let plans: any PlanRepository

    public init(health: any HealthDataSource, plans: any PlanRepository) {
        self.health = health
        self.plans = plans
    }

    public func execute() async -> LaunchRoute {
        let status = await health.authorizationRequestStatus()
        let hasPlan = await plans.hasActivePlan()
        return Self.route(requestStatus: status, hasActivePlan: hasPlan)
    }

    /// Never requested comes first, even when a plan exists.
    public static func route(requestStatus: HealthAuthorizationRequestStatus, hasActivePlan: Bool) -> LaunchRoute {
        switch requestStatus {
        case .shouldRequest: .connectHealth
        case .alreadyRequested: hasActivePlan ? .home : .startingPoint
        }
    }
}
