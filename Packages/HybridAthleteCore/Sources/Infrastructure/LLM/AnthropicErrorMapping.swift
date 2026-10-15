import Foundation
import FoundationModels
import ClaudeForFoundationModels
import Domain

/// How ClaudeForFoundationModels (0.2.3) surfaces Anthropic failures, read from its
/// `ErrorMapper` and `ClaudeClient`:
/// - 401 `authentication_error` -> `ClaudeError.missingCredential` (also thrown
///   when no key is configured; the gate makes sure one is).
/// - 429 `rate_limit_error` and 529 `overloaded_error` -> `LanguageModelError.rateLimited`
///   with no reset date (the package does not read Retry-After). The overloaded
///   case is told apart by its message ("Overloaded", or "HTTP 529: ..." without a JSON body).
/// - Everything else (`invalid_request_error` for a low credit balance,
///   `permission_error`, `api_error` for 5xx) is the package's own `APIError`, which
///   is `package`-internal; its description reads "<type>: <message>".
/// - Network failures arrive as `URLError` (timeouts as `LanguageModelError.timeout`).
/// Returns nil for anything that is not Anthropic-specific, so the shared mapping
/// handles it.
enum AnthropicErrorMapping {
    static func llmError(_ error: any Error, now: Date) -> LLMError? {
        if error is ClaudeError { return .authenticationFailed }
        if let error = error as? LanguageModelError, case .rateLimited(let limit) = error {
            let detail = limit.debugDescription.lowercased()
            if detail.contains("overloaded") || detail.contains("http 529") { return .providerUnavailable }
            return .rateLimited(retryAfter: limit.resetDate.map { max(0, $0.timeIntervalSince(now)) })
        }
        if let error = error as? URLError {
            return error.code == .timedOut ? .timedOut : .networkUnavailable
        }
        let description = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return apiError(description: description)
    }

    /// The package's `APIError` by its description ("invalid_request_error: Your credit balance is too low ...").
    static func apiError(description: String) -> LLMError? {
        let text = description.lowercased()
        if text.contains("credit balance") || text.contains("billing") { return .billingProblem }
        if text.hasPrefix("authentication_error") || text.hasPrefix("permission_error") { return .authenticationFailed }
        if text.hasPrefix("rate_limit_error") { return .rateLimited(retryAfter: nil) }
        if text.hasPrefix("overloaded_error") || text.hasPrefix("api_error") { return .providerUnavailable }
        return nil
    }
}
