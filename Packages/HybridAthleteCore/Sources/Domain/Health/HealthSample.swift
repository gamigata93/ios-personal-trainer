import Foundation

/// A single measured value from a health source.
public struct HealthSample: Sendable, Equatable, Codable {
    public let value: Double
    public let unit: String
    public let date: Date
    public let sourceName: String

    public init(value: Double, unit: String, date: Date, sourceName: String) {
        self.value = value
        self.unit = unit
        self.date = date
        self.sourceName = sourceName
    }
}

/// Quantity metrics read as individual samples.
public enum HealthMetricKind: Sendable, Equatable {
    case vo2Max
    case restingHeartRate

    /// The unit every sample of this kind is expressed in.
    public var unitLabel: String {
        switch self {
        case .vo2Max: "ml/(kg·min)"
        case .restingHeartRate: "bpm"
        }
    }
}

public struct VO2MaxSection: Sendable, Equatable {
    public let status: ReadStatus
    public let latest: HealthSample?
    /// Up to 10, newest first.
    public let recent: [HealthSample]

    public init(status: ReadStatus, latest: HealthSample?, recent: [HealthSample]) {
        self.status = status
        self.latest = latest
        self.recent = recent
    }

    public static func unread(_ status: ReadStatus) -> VO2MaxSection {
        VO2MaxSection(status: status, latest: nil, recent: [])
    }
}

public struct RestingHeartRateSection: Sendable, Equatable {
    public static let windowDays = 30

    public let status: ReadStatus
    public let latest: HealthSample?
    public let average30Days: Double?
    public let sampleCount30Days: Int

    public init(status: ReadStatus, latest: HealthSample?, average30Days: Double?, sampleCount30Days: Int) {
        self.status = status
        self.latest = latest
        self.average30Days = average30Days
        self.sampleCount30Days = sampleCount30Days
    }

    public static func unread(_ status: ReadStatus) -> RestingHeartRateSection {
        RestingHeartRateSection(status: status, latest: nil, average30Days: nil, sampleCount30Days: 0)
    }

    /// Builds the section from the samples of the last 30 days, plus the latest
    /// sample overall for when the window is empty.
    public static func summarizing(windowSamples: [HealthSample], latestOverall: HealthSample?) -> RestingHeartRateSection {
        let latest = windowSamples.max(by: { $0.date < $1.date }) ?? latestOverall
        let average = windowSamples.isEmpty
            ? nil
            : windowSamples.map(\.value).reduce(0, +) / Double(windowSamples.count)
        return RestingHeartRateSection(
            status: latest == nil ? .emptyOrNotAllowed : .ok,
            latest: latest,
            average30Days: average,
            sampleCount30Days: windowSamples.count
        )
    }
}
