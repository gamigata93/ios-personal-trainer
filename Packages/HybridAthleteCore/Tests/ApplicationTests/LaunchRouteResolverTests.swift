import Foundation
import Testing
import Application
import Domain

struct LaunchRouteResolverTests {
    private func Plans(hasPlan: Bool) -> FakePlanRepository {
        FakePlanRepository(plan: hasPlan ? FakePlanRepository.samplePlan : nil)
    }

    @Test(arguments: [false, true])
    func neverRequestedConnectsHealthEvenWithAPlan(hasPlan: Bool) async {
        let health = FakeHealthDataSource()
        await health.set(requestStatus: .shouldRequest)
        #expect(await LaunchRouteResolver(health: health, plans: Plans(hasPlan: hasPlan)).execute() == .connectHealth)
    }

    @Test func requestedWithoutPlanOpensStartingPoint() async {
        #expect(await LaunchRouteResolver(health: FakeHealthDataSource(), plans: Plans(hasPlan: false)).execute() == .startingPoint)
    }

    @Test func requestedWithPlanOpensHome() async {
        #expect(await LaunchRouteResolver(health: FakeHealthDataSource(), plans: Plans(hasPlan: true)).execute() == .home)
    }

    @Test func pureRuleMatches() {
        #expect(LaunchRouteResolver.route(requestStatus: .shouldRequest, hasActivePlan: true) == .connectHealth)
        #expect(LaunchRouteResolver.route(requestStatus: .alreadyRequested, hasActivePlan: false) == .startingPoint)
        #expect(LaunchRouteResolver.route(requestStatus: .alreadyRequested, hasActivePlan: true) == .home)
    }
}
