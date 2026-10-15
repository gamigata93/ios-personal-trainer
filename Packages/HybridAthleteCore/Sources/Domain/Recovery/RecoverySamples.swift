import Foundation

/// One HRV reading (SDNN, milliseconds). Never RMSSD.
public struct HRVSample: Sendable, Equatable, Codable {
    public let date: Date
    public let valueMs: Double
    /// Already normalized ("Apple Watch", never a person's device name).
    public let source: String

    public init(date: Date, valueMs: Double, source: String) {
        self.date = date
        self.valueMs = valueMs
        self.source = source
    }
}

/// One resting heart rate estimate, published by Apple about once a day.
public struct RestingHRSample: Sendable, Equatable, Codable {
    public let endDate: Date
    public let bpm: Double
    /// Already normalized.
    public let source: String

    public init(endDate: Date, bpm: Double, source: String) {
        self.endDate = endDate
        self.bpm = bpm
        self.source = source
    }
}

/// One night's HRV from one source, assigned to the wake-up date.
public struct HRVNight: Sendable, Equatable, Codable {
    public enum WindowKind: String, Sendable, Equatable, Codable {
        /// The night's sleep window, both ends included.
        case sleep
        /// 00:00 (inclusive) to 08:00 (exclusive) local, when there is no sleep night.
        case overnightFallback
    }

    public let wakeDate: LocalDate
    /// Unrounded mean of the chosen source's samples.
    public let meanMs: Double
    public let sampleCount: Int
    public let windowKind: WindowKind
    public let sourceLabel: String

    public init(wakeDate: LocalDate, meanMs: Double, sampleCount: Int, windowKind: WindowKind, sourceLabel: String) {
        self.wakeDate = wakeDate
        self.meanMs = meanMs
        self.sampleCount = sampleCount
        self.windowKind = windowKind
        self.sourceLabel = sourceLabel
    }
}

/// One day's resting heart rate from one source.
public struct RestingHRDay: Sendable, Equatable, Codable {
    public let date: LocalDate
    public let bpm: Double
    public let sourceLabel: String

    public init(date: LocalDate, bpm: Double, sourceLabel: String) {
        self.date = date
        self.bpm = bpm
        self.sourceLabel = sourceLabel
    }
}
