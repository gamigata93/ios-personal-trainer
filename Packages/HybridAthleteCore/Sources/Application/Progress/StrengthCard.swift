import Foundation
import Domain

/// The strength row under the day card (Home and Calendar): the session's name,
/// minutes and exercise count, and its status. Opens the strength detail.
public struct StrengthCard: Sendable, Equatable {
    public let sessionID: String
    /// "Strength: Lower body A".
    public let name: String
    /// "30 min · 5 exercises".
    public let meta: String
    public let status: SessionStatus
    /// "Upcoming".
    public let statusText: String

    static func make(_ session: StrengthSession?, status: SessionStatus?) -> StrengthCard? {
        guard let session, let status else { return nil }
        return StrengthCard(
            sessionID: session.id,
            name: session.name,
            meta: "\(session.minutes) min · \(session.exercises.count) exercises",
            status: status,
            statusText: HomeFormat.statusText(status)
        )
    }
}
