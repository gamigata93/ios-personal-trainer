import Foundation

public enum NormMetric: String, Sendable, Equatable, Codable {
    case vo2max
    case restingHeartRate

    /// Whether a higher value is the better one.
    public var higherIsBetter: Bool {
        switch self {
        case .vo2max: true
        case .restingHeartRate: false
        }
    }
}

/// The population a table describes. `all` covers everyone regardless of sex.
public enum NormSex: String, Sendable, Equatable, Codable {
    case male
    case female
    case all
}

public struct NormAnchor: Sendable, Equatable, Codable {
    /// Percentile of the population at or below `v`.
    public let p: Double
    public let v: Double

    public init(p: Double, v: Double) {
        self.p = p
        self.v = v
    }
}

/// Published reference values for one metric, sex and age band. Plain data
/// loaded from the bundled Norms.json; every table names its source.
public struct NormTable: Sendable, Equatable, Codable {
    public let id: String
    public let metric: NormMetric
    public let sex: NormSex
    public let ageMin: Int
    public let ageMax: Int
    public let unit: String
    public let anchors: [NormAnchor]
    public let source: String

    public init(
        id: String,
        metric: NormMetric,
        sex: NormSex,
        ageMin: Int,
        ageMax: Int,
        unit: String,
        anchors: [NormAnchor],
        source: String
    ) {
        self.id = id
        self.metric = metric
        self.sex = sex
        self.ageMin = ageMin
        self.ageMax = ageMax
        self.unit = unit
        self.anchors = anchors
        self.source = source
    }

    public func covers(age: Int) -> Bool {
        (ageMin...ageMax).contains(age)
    }
}

/// The whole Norms.json document.
public struct NormDocument: Sendable, Equatable, Codable {
    public let schemaVersion: Int
    public let tables: [NormTable]

    public init(schemaVersion: Int, tables: [NormTable]) {
        self.schemaVersion = schemaVersion
        self.tables = tables
    }
}

/// Why the norm data cannot be used.
public enum NormDataError: Error, Sendable, Equatable {
    case missing
    case malformed(String)
}
