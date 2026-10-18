import Foundation

/// Plain English text for the Home screen. Pure and locale-independent, so the
/// same inputs always give the same words.
public enum HomeFormat {
    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// 5-11 "Good morning", 12-17 "Good afternoon", otherwise "Good evening".
    public static func greeting(hour: Int) -> String {
        switch hour {
        case 5...11: "Good morning"
        case 12...17: "Good afternoon"
        default: "Good evening"
        }
    }

    /// "Oct".
    public static func shortMonth(_ date: LocalDate) -> String {
        String(monthNames[date.month - 1].prefix(3))
    }

    /// "Wednesday, 28 October".
    public static func longDate(_ date: LocalDate) -> String {
        "\(date.weekday.name), \(date.day) \(monthNames[date.month - 1])"
    }

    /// "Wednesday 28 October" (for accessibility labels).
    public static func spokenDate(_ date: LocalDate) -> String {
        "\(date.weekday.name) \(date.day) \(monthNames[date.month - 1])"
    }

    /// "Wed 28 Oct".
    public static func shortDate(_ date: LocalDate) -> String {
        "\(shortWeekday(date.weekday)) \(date.day) \(shortMonth(date))"
    }

    /// "Wed".
    public static func shortWeekday(_ weekday: Weekday) -> String {
        String(weekday.name.prefix(3))
    }

    /// "12 - 18 Oct", or "26 Oct - 1 Nov" when the range crosses a month.
    public static func weekRangeLabel(start: LocalDate, end: LocalDate) -> String {
        if start.month == end.month, start.year == end.year {
            return "\(start.day) - \(end.day) \(shortMonth(end))"
        }
        return "\(start.day) \(shortMonth(start)) - \(end.day) \(shortMonth(end))"
    }

    /// "5K race", "10K race", "Half marathon race", "Marathon race" within
    /// 0.5 km of 5, 10, 21.1 and 42.2; otherwise "{n} km race".
    public static func raceTitle(distanceKm: Double) -> String {
        let named: [(Double, String)] = [(5, "5K race"), (10, "10K race"), (21.1, "Half marathon race"), (42.2, "Marathon race")]
        if let match = named.first(where: { abs($0.0 - distanceKm) <= 0.5 }) {
            return match.1
        }
        return "\(km(distanceKm)) km race"
    }

    /// "~25 min", or nil without an estimate.
    public static func estimatedTime(minutes: Int?) -> String? {
        minutes.map { "~\($0) min" }
    }

    /// "7.5" or "6": one decimal at most, none for whole numbers.
    public static func km(_ value: Double) -> String {
        let tenths = (value * 10).rounded()
        return tenths.truncatingRemainder(dividingBy: 10) == 0
            ? String(Int(tenths / 10))
            : String(format: "%.1f", tenths / 10)
    }

    /// "7.5 km · ~40 min", or "7.5 km" without an estimate.
    public static func sessionMeta(_ session: PlannedSession) -> String {
        [ "\(km(session.distanceKm)) km", estimatedTime(minutes: session.estimatedMinutes) ]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// "Wednesday 28 October, Easy run, today": the date, the session (or "Race
    /// day" / "Rest day"), then the status, or "today" for today without one.
    /// A strength session is read after the run: "..., Easy run, upcoming, plus Strength: Core A, upcoming".
    public static func dayAccessibilityLabel(
        date: LocalDate, sessionName: String?, isRaceDay: Bool, status: SessionStatus?, isToday: Bool,
        strength: (name: String, status: SessionStatus)? = nil
    ) -> String {
        var parts = [spokenDate(date)]
        if isRaceDay {
            parts.append("Race day")
        } else if let sessionName {
            parts.append(sessionName)
        } else {
            parts.append("Rest day")
        }
        if let status {
            parts.append(statusText(status).lowercased())
        } else if isToday {
            parts.append("today")
        }
        if let strength {
            parts.append("plus \(strength.name)")
            parts.append(statusText(strength.status).lowercased())
        }
        return parts.joined(separator: ", ")
    }

    /// "Completed", "Missed", "Not recorded", "Today", "Upcoming".
    public static func statusText(_ status: SessionStatus) -> String {
        switch status {
        case .completed: "Completed"
        case .missed: "Missed"
        case .notRecorded: "Not recorded"
        case .today: "Today"
        case .upcoming: "Upcoming"
        }
    }
}
