import Foundation

/// One running workout as the health source reports it: just enough to match it
/// to a planned session, plus its average and max heart rate. No route or source.
public struct RunSummary: Sendable, Equatable {
    /// The health store's workout UUID.
    public let id: String
    public let startDate: Date
    /// 0 when the source recorded no distance.
    public let distanceMeters: Double
    public let durationSeconds: Double
    public let averageHeartRate: Double?
    public let maxHeartRate: Double?

    public init(
        id: String, startDate: Date, distanceMeters: Double, durationSeconds: Double,
        averageHeartRate: Double? = nil, maxHeartRate: Double? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
    }
}
