import Foundation

/// How a personal record is presented. Records are scaled estimates for
/// display only and never feed plan sizing.
public struct PersonalRecordDisplay: Sendable, Equatable {
    public static let olderAfterDays = 365

    public let record: PersonalRecord
    /// The time was scaled from a run that was not exactly on the distance.
    public let isEstimated: Bool
    /// More than 365 days old.
    public let isOlder: Bool
    /// Set within the last 30 days.
    public let isNew: Bool

    public init(record: PersonalRecord, now: Date) {
        self.record = record
        isEstimated = record.timeIsNormalized
        isOlder = now.timeIntervalSince(record.date) > TimeInterval(Self.olderAfterDays) * 86_400
        isNew = record.isNew
    }
}

/// One row of the records card: a distance and its record, if any.
public struct PersonalRecordRow: Sendable, Equatable {
    public let distance: RecordDistance
    public let record: PersonalRecordDisplay?

    public init(distance: RecordDistance, record: PersonalRecordDisplay?) {
        self.distance = distance
        self.record = record
    }
}
