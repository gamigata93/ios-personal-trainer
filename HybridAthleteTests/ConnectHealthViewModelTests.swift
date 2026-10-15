import Foundation
import Testing
import Domain
import Application
@testable import HybridAthlete

@MainActor
struct ConnectHealthViewModelTests {
    @Test(arguments: [nil, HealthDataError.notAllowed, .failed] as [HealthDataError?])
    func allowRequestsOnceAndAlwaysMovesOn(error: HealthDataError?) async {
        let health = StubHealthDataSource(status: .shouldRequest, requestError: error)
        var finished = 0
        let viewModel = ConnectHealthViewModel(
            requestHealthAccess: RequestHealthAccess(health: health),
            onFinished: { finished += 1 }
        )

        await viewModel.allow()
        await viewModel.allow() // a second tap does nothing

        #expect(await health.requestCount == 1)
        #expect(finished == 1)
    }
}
