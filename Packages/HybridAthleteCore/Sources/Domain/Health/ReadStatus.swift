import Foundation

/// The outcome of reading one section of Apple Health.
///
/// HealthKit hides read permission: an empty result can mean "no data" or
/// "no access", so the two share one case.
public enum ReadStatus: String, Sendable, Equatable {
    case ok
    case emptyOrNotAllowed
    /// The phone was locked, so Health data was protected. Retry after unlock.
    case locked
    case error
}

/// Why a health data source could not answer. Adapters translate their
/// framework errors into these cases.
public enum HealthDataError: Error, Sendable, Equatable {
    /// Health data does not exist on this device (e.g. some iPads, Mac).
    case unavailable
    /// The data is protected while the phone is locked.
    case locked
    /// Access was denied or not yet decided.
    case notAllowed
    case failed
}

/// Whether the system would still show the Health permission sheet. HealthKit
/// never says what the user granted, only whether they have been asked.
public enum HealthAuthorizationRequestStatus: Sendable, Equatable {
    case shouldRequest
    case alreadyRequested
}
