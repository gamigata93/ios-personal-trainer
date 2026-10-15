import Foundation

/// Which dated item a card shows: the newest one dated today or up to
/// `maxAgeDays` days before.
public enum RecentSelection<Item: Sendable & Equatable>: Sendable, Equatable {
    case shown(Item, label: String)
    /// Items exist, but none is recent.
    case noRecent(lastDate: LocalDate)
    case noData

    public static func select(
        _ items: [Item],
        date: (Item) -> LocalDate,
        today: LocalDate,
        maxAgeDays: Int,
        label: (LocalDate, LocalDate) -> String
    ) -> RecentSelection {
        guard let latest = items.map(date).max() else { return .noData }
        guard let newest = items.filter({ date($0) <= today }).max(by: { date($0) < date($1) }) else {
            return .noRecent(lastDate: latest)
        }
        let newestDate = date(newest)
        guard newestDate >= today.adding(days: -maxAgeDays) else { return .noRecent(lastDate: newestDate) }
        return .shown(newest, label: label(newestDate, today))
    }
}

/// Labels for the shown date.
public enum RecoveryLabel {
    /// "Last night", "Yesterday", otherwise "Mon 26 Oct" (as the Sleep card).
    public static func night(_ date: LocalDate, today: LocalDate) -> String {
        SleepSelection.label(for: date, today: today)
    }

    /// "Today", "Yesterday", otherwise "Mon 26 Oct".
    public static func day(_ date: LocalDate, today: LocalDate) -> String {
        switch date.days(to: today) {
        case 0: "Today"
        case 1: "Yesterday"
        default: HomeFormat.shortDate(date)
        }
    }
}
