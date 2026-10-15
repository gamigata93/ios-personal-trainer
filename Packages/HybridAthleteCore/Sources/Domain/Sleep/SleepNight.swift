import Foundation

/// One sleep sample's value, as Health reports it.
public enum SleepStage: String, Sendable, Equatable, Codable, CaseIterable {
    case inBed, awake, asleepUnspecified, core, deep, rem

    /// Unspecified, core, deep and REM are asleep; in bed and awake are not.
    public var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .core, .deep, .rem: true
        case .inBed, .awake: false
        }
    }
}

/// One sleep sample: a stretch of one stage from one source.
public struct SleepSegment: Sendable, Equatable, Codable {
    public let start: Date
    public let end: Date
    public let stage: SleepStage
    /// Already normalized ("Apple Watch", never a person's device name).
    public let source: String

    public init(start: Date, end: Date, stage: SleepStage, source: String) {
        self.start = start
        self.end = end
        self.stage = stage
        self.source = source
    }
}

/// One night from one source, assigned to the date the user woke up.
/// Minutes are unions of intervals, so overlapping samples never count twice.
public struct SleepNight: Sendable, Equatable, Codable {
    public let wakeDate: LocalDate
    /// The first asleep moment.
    public let sleepStart: Date
    /// The last asleep moment.
    public let wakeTime: Date
    public let asleepMinutes: Int
    public let deepMinutes: Int
    public let coreMinutes: Int
    public let remMinutes: Int
    public let unspecifiedMinutes: Int
    public let awakeMinutes: Int
    /// First to last asleep or awake segment.
    public let timeInBedMinutes: Int
    /// Core, deep or REM were recorded (an Apple Watch with sleep tracking).
    public let hasStages: Bool
    public let sourceLabel: String

    public init(
        wakeDate: LocalDate,
        sleepStart: Date,
        wakeTime: Date,
        asleepMinutes: Int,
        deepMinutes: Int,
        coreMinutes: Int,
        remMinutes: Int,
        unspecifiedMinutes: Int,
        awakeMinutes: Int,
        timeInBedMinutes: Int,
        hasStages: Bool,
        sourceLabel: String
    ) {
        self.wakeDate = wakeDate
        self.sleepStart = sleepStart
        self.wakeTime = wakeTime
        self.asleepMinutes = asleepMinutes
        self.deepMinutes = deepMinutes
        self.coreMinutes = coreMinutes
        self.remMinutes = remMinutes
        self.unspecifiedMinutes = unspecifiedMinutes
        self.awakeMinutes = awakeMinutes
        self.timeInBedMinutes = timeInBedMinutes
        self.hasStages = hasStages
        self.sourceLabel = sourceLabel
    }
}
