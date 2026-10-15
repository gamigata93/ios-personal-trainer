import Foundation
import Domain

/// The card for one selected day, shared by Home and the Calendar so both look
/// and behave the same: a session (with an arrow to its detail), a rest day or
/// race day.
public enum DayCard: Sendable, Equatable {
    case session(Session)
    case rest
    /// The race title, e.g. "10K race".
    case race(String)

    public struct Session: Sendable, Equatable {
        public let sessionID: String
        public let type: SessionType
        public let name: String
        /// "7.5 km · ~40 min".
        public let meta: String
        public let status: SessionStatus
        /// "Upcoming".
        public let statusText: String
        /// "Moved from Mon 26 Oct" when an edit put it on another day.
        public let movedFrom: String?
    }

    /// Race day wins over a session; a day without either is a rest day.
    static func make(session: PlannedSession?, status: SessionStatus?, isRaceDay: Bool, raceTitle: String) -> DayCard {
        if isRaceDay { return .race(raceTitle) }
        guard let session, let status else { return .rest }
        return .session(Session(
            sessionID: session.id,
            type: session.type,
            name: session.name,
            meta: HomeFormat.sessionMeta(session),
            status: status,
            statusText: HomeFormat.statusText(status),
            movedFrom: PlanEditFormat.movedFrom(session)
        ))
    }
}

/// The muted line shown when completed runs could not be read because the phone is locked.
enum ProgressLockedLine {
    /// "Your phone is locked. Showing progress from today 07:40.", or nil when not locked.
    static func text(runs: CompletedRunsResult, now: Date, calendar: Calendar) -> String? {
        guard runs.isLocked else { return nil }
        guard let asOf = runs.asOf else { return "Your phone is locked. Progress updates after you unlock it." }
        return "Your phone is locked. Showing progress from \(UpdatedLabel.text(now: now, then: asOf, calendar: calendar))."
    }
}
