import Foundation

/// One running workout as the health source reports it: just enough to match it
/// to a planned session. No route, heart rate or source.
public struct RunSummary: Sendable, Equatable {
    /// The health store's workout UUID.
    public let id: String
    public let startDate: Date
    /// 0 when the source recorded no distance.
    public let distanceMeters: Double
    public let durationSeconds: Double

    public init(id: String, startDate: Date, distanceMeters: Double, durationSeconds: Double) {
        self.id = id
        self.startDate = startDate
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
    }
}
