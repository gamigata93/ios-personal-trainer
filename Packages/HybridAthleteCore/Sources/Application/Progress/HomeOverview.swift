import Foundation
import Domain

/// Everything the Home screen shows, already worded. The view model passes it
/// through; the view only picks colors and fonts.
public struct HomeOverview: Sendable, Equatable {
    public struct Header: Sendable, Equatable {
        /// "Wednesday, 28 October".
        public let dateCaption: String
        /// "Good morning".
        public let greeting: String
    }

    public struct PlanCard: Sendable, Equatable {
        /// "10K race".
        public let raceTitle: String
        /// 0...1 for the ring; nil before anything is due.
        public let adherence: Double?
        /// "86%" or "-".
        public let ringValue: String
        /// "on plan", or "Starts Mon 12 Oct" before the plan starts.
        public let ringCaption: String
        /// "Plan adherence 86 percent" or "Plan has not started".
        public let ringAccessibilityLabel: String
        /// "39", "Race day" or "Finished".
        public let countdownValue: String
        /// "days to go" next to a number; nil for race day and after.
        public let countdownUnit: String?
        /// "39 days to go", "Race day" or "Finished".
        public var countdownAccessibilityLabel: String {
            [countdownValue, countdownUnit].compactMap { $0 }.joined(separator: " ")
        }
        public let pill: Pill?
        /// "Week 3 of 8" while the plan runs.
        public let weekCaption: String?
    }

    public struct Pill: Sendable, Equatable {
        /// "Base phase" or "Starts Mon 12 Oct".
        public let text: String
        /// Muted before the plan starts, accent otherwise.
        public let isMuted: Bool
    }

    public struct Week: Sendable, Equatable {
        public let index: Int
        /// "26 Oct - 1 Nov".
        public let rangeLabel: String
        public let canGoBack: Bool
        public let canGoForward: Bool
        public let days: [Day]
    }

    public struct Day: Sendable, Equatable, Identifiable {
        public var id: String { date.description }
        public let date: LocalDate
        /// "Wed".
        public let weekdayShort: String
        /// "28".
        public let dayNumber: String
        public let isToday: Bool
        public let isSelected: Bool
        public let sessionType: SessionType?
        public let status: SessionStatus?
        public let isRaceDay: Bool
        /// "Wednesday 28 October, Easy run, today".
        public let accessibilityLabel: String
    }

    /// The shared day card (Home and Calendar).
    public typealias SelectedCard = DayCard
    public typealias SessionCard = DayCard.Session

    public struct UpNext: Sendable, Equatable {
        /// Opens the session detail.
        public let sessionID: String
        /// "Up next · Fri 30 Oct".
        public let caption: String
        public let type: SessionType
        public let name: String
        public let meta: String
    }

    public let header: Header
    public let planCard: PlanCard
    /// Nil after race day.
    public let week: Week?
    public let selectedDate: LocalDate?
    public let selectedCard: SelectedCard?
    public let upNext: UpNext?
    /// "Your phone is locked. Showing progress from today 07:40." Only when locked.
    public let lockedLine: String?
    /// Sleep, HRV and resting heart rate, with the section-level lines.
    public let recovery: RecoveryOverview
    /// Sessions completed and sessions due, behind the ring's percentage.
    public let completedCount: Int
    public let dueCount: Int
}
