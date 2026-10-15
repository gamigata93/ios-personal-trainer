import Foundation

/// The current time. Injected so logic never calls `Date()` directly.
public protocol Clock: Sendable {
    func now() -> Date
}
