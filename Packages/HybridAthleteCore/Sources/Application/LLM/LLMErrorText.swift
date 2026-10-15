import Foundation
import Domain

/// Readable sentences for model failures, for the Generating screen and the Lab.
public struct LLMErrorText: Sendable {
    private let calendar: Calendar
    private let locale: Locale
    private let now: @Sendable () -> Date

    public init(calendar: Calendar, locale: Locale, now: @escaping @Sendable () -> Date) {
        self.calendar = calendar
        self.locale = locale
        self.now = now
    }

    public func message(_ error: LLMError) -> String {
        switch error {
        case .unavailable(let availability):
            availability.message
        case .quotaLimitReached(let reset):
            reset.map { "Today's Apple Intelligence limit was reached. It resets \(resetText($0))." }
                ?? "Today's Apple Intelligence limit was reached. Try again later."
        case .networkUnavailable:
            "This model needs a network connection. Check your connection and try again."
        case .guardrailViolation:
            "Apple's guardrails declined this request."
        case .contextTooLarge:
            "The request is too long for this model's context."
        case .timedOut:
            "The model took too long to answer."
        case .cancelled:
            "Cancelled."
        case .malformedOutput(let detail):
            "The model's answer didn't fit the expected shape. \(detail.replacingOccurrences(of: "\n", with: " "))"
        case .invalidPlan:
            "The model's plan broke the rules. Try again."
        case .authenticationFailed:
            "Anthropic rejected the API key."
        case .rateLimited(let retryAfter):
            retryAfter.map { "Anthropic is rate limiting requests. Try again in \(Int($0.rounded(.up))) s." }
                ?? "Anthropic is rate limiting requests. Try again in a moment."
        case .billingProblem:
            "Your Anthropic credit balance is too low. Add credits in the Claude Console."
        case .providerUnavailable:
            "Anthropic is temporarily unavailable."
        case .spendLimit(let text):
            text
        case .other(let detail):
            "The model failed: \(detail)"
        }
    }

    /// "14:30" today, "tomorrow 09:00", otherwise "Mon 2 Nov 09:00" (device time format).
    public func resetText(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        let time = date.formatted(style)
        let today = LocalDate(date: now(), calendar: calendar)
        let day = LocalDate(date: date, calendar: calendar)
        if day == today { return time }
        if day == today.adding(days: 1) { return "tomorrow \(time)" }
        return "\(HomeFormat.shortDate(day)) \(time)"
    }

    /// "Below limit", "Nearing usage limit", "Limit reached, resets 14:30".
    public func quotaLine(_ quota: QuotaStatus) -> String {
        switch quota.state {
        case .belowLimit: "Below limit"
        case .nearingLimit: "Nearing usage limit"
        case .limitReached: quota.resetDate.map { "Limit reached, resets \(resetText($0))" } ?? "Limit reached"
        }
    }
}
