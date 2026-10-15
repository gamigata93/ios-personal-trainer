import Foundation
import Domain

/// Shows the Health permission sheet for every type the app reads.
public struct RequestHealthAccess: Sendable {
    private let health: any HealthDataSource

    public init(health: any HealthDataSource) {
        self.health = health
    }

    public func execute() async throws(HealthDataError) {
        try await mappingHealthErrors { try await health.requestAccess() }
    }
}
