import Foundation

/// A measured value with when it was measured.
public struct MetricReading: Sendable, Equatable {
    public let value: Double
    public let date: Date

    public init(value: Double, date: Date) {
        self.value = value
        self.date = date
    }
}

/// Who a comparison is made against.
public enum NormPopulation: Sendable, Equatable {
    case ageAndSex
    /// Sex not known; compared with all adults of the same age.
    case allAdults
}

/// Why a scale cannot be shown for a value that exists.
public enum NormUnavailableReason: Sendable, Equatable {
    case ageUnknown
    case belowMinimumAge(Int)
    case aboveMaximumAge(Int)
    case sexNotSet
    case normsUnavailable
}

public struct NormComparison: Sendable, Equatable {
    public let result: PercentileResult
    public let population: NormPopulation
    public let tableId: String
    public let source: String

    public init(result: PercentileResult, population: NormPopulation, tableId: String, source: String) {
        self.result = result
        self.population = population
        self.tableId = tableId
        self.source = source
    }
}

public enum NormOutcome: Sendable, Equatable {
    case compared(NormComparison)
    case unavailable(NormUnavailableReason)
}

/// One metric on the dashboard: the latest reading (if any) and how it compares.
public struct MetricBaseline: Sendable, Equatable {
    public let reading: MetricReading?
    /// `nil` when there is no reading to compare.
    public let norm: NormOutcome?

    public init(reading: MetricReading?, norm: NormOutcome?) {
        self.reading = reading
        self.norm = norm
    }
}
