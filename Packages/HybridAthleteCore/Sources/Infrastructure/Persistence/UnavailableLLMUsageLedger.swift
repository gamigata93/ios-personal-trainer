import Foundation
import Application
import Domain

/// Stands in when the database could not be opened: nothing is stored and every
/// read fails, so the spend gate blocks Claude runs (the monthly cap cannot be
/// checked) instead of letting them run unmetered.
public struct UnavailableLLMUsageLedger: LLMUsageLedger {
    struct Unavailable: Error {}

    public init() {}

    public func record(_ record: LLMCallRecord) async {}
    public func records(since date: Date?) async throws -> [LLMCallRecord] { throw Unavailable() }
    public func clear() async throws { throw Unavailable() }
    public func firstRecordDate() async throws -> Date? { throw Unavailable() }
}
