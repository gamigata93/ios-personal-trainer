import Foundation

/// How long ago data was read, for "updated …" lines.
public enum UpdatedLabel {
    /// "just now" under a minute, "{n} min ago" under an hour, then "today HH:mm",
    /// "yesterday HH:mm", otherwise "d MMM". Times use `calendar`'s time zone.
    public static func text(now: Date, then: Date, calendar: Calendar) -> String {
        let elapsed = now.timeIntervalSince(then)
        if elapsed < 60 {
            return "just now"
        }
        if elapsed < 3_600 {
            return "\(Int(elapsed / 60)) min ago"
        }
        if calendar.isDate(then, inSameDayAs: now) {
            return "today \(format(then, "HH:mm", calendar))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(then, inSameDayAs: yesterday) {
            return "yesterday \(format(then, "HH:mm", calendar))"
        }
        return format(then, "d MMM", calendar)
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
