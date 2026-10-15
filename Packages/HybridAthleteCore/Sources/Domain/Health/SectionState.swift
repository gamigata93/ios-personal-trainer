import Foundation

/// The parts of Apple Health that are read and cached separately. Run heart
/// rate, records, volume and the workout count all derive from `workouts`.
public enum HealthSection: String, Sendable, Equatable, CaseIterable {
    case profile
    case vo2Max
    case restingHeartRate
    case workouts
}

/// Where one section stands while the app shows it.
public enum SectionState<Value: Sendable>: Sendable {
    /// Not known yet and nothing cached.
    case loading
    case ready(Value, asOf: Date, fromCache: Bool)
    /// The phone was locked. Shows the cached value, if there is one.
    case locked(cachedValue: Value?, asOf: Date?)
    /// No data, or no access: HealthKit does not say which.
    case emptyOrNotAllowed
    case failed

    /// The value to show: fresh, cached, or cached behind a lock.
    public var value: Value? {
        switch self {
        case .ready(let value, _, _): value
        case .locked(let cached, _): cached
        case .loading, .emptyOrNotAllowed, .failed: nil
        }
    }

    public var asOf: Date? {
        switch self {
        case .ready(_, let asOf, _): asOf
        case .locked(_, let asOf): asOf
        case .loading, .emptyOrNotAllowed, .failed: nil
        }
    }

    public var isLoading: Bool {
        if case .loading = self { true } else { false }
    }

    public var isLocked: Bool {
        if case .locked = self { true } else { false }
    }
}

extension SectionState: Equatable where Value: Equatable {}
