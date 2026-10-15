import Foundation

/// A run the user did, placed on the local day it started.
public struct CompletedRun: Sendable, Equatable, Codable {
    public let id: String
    public let localDate: LocalDate
    public let distanceKm: Double
    public let durationSeconds: Double

    public init(id: String, localDate: LocalDate, distanceKm: Double, durationSeconds: Double) {
        self.id = id
        self.localDate = localDate
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
    }
}

/// Where a planned session stands. Ratings come later.
public enum SessionStatus: String, Sendable, Equatable, CaseIterable, Codable {
    case completed, missed, notRecorded, today, upcoming

    /// Precedence: completed (a run matched) > missed (the user said so) >
    /// notRecorded (past) > today > upcoming.
    public static func of(date: LocalDate, isMatched: Bool, isMissed: Bool = false, today: LocalDate) -> SessionStatus {
        if isMatched { return .completed }
        if isMissed { return .missed }
        if date < today { return .notRecorded }
        return date == today ? .today : .upcoming
    }
}
