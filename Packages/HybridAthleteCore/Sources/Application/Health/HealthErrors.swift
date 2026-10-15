import Foundation
import Domain

/// Runs a port call and narrows any error it throws to `HealthDataError`.
func mappingHealthErrors<T>(_ body: () async throws -> T) async throws(HealthDataError) -> T {
    do {
        return try await body()
    } catch let error as HealthDataError {
        throw error
    } catch {
        throw .failed
    }
}

extension ReadStatus {
    /// How a failed read is shown. "Not allowed" looks like "no data" on purpose:
    /// HealthKit does not reveal which one it is.
    init(_ error: any Error) {
        switch error as? HealthDataError {
        case .locked: self = .locked
        case .notAllowed: self = .emptyOrNotAllowed
        case .unavailable, .failed, nil: self = .error
        }
    }
}
