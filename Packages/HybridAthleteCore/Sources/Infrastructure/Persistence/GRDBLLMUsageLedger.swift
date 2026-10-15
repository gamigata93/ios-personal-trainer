import Foundation
import GRDB
import Application
import Domain

/// The usage ledger in the app database (table llm_usage, migration v2_llm_usage).
/// Rows hold token counts and costs only. Recording is best effort: a failed
/// write is dropped, never thrown into a model call.
public struct GRDBLLMUsageLedger: LLMUsageLedger {
    private let database: DatabaseProvider

    public init(database: DatabaseProvider) {
        self.database = database
    }

    public func record(_ record: LLMCallRecord) async {
        _ = try? await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO llm_usage (createdAt, provider, modelId, purpose, success, errorKind, uncachedInput,
                        cacheRead, cacheWrite, output, reasoning, latencyMs, costMicros, priceTableVersion)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    GRDBPlanRepository.timestamp(record.createdAt), record.provider.rawValue, record.modelId,
                    record.purpose.rawValue, record.success, record.errorKind, record.usage.uncachedInput,
                    record.usage.cacheRead, record.usage.cacheWrite, record.usage.output, record.usage.reasoning,
                    record.latencyMs, record.costMicros, record.priceTableVersion,
                ]
            )
        }
    }

    public func records(since date: Date?) async throws -> [LLMCallRecord] {
        try await database.writer.read { db in
            let rows: [Row]
            if let date {
                // Timestamps are fixed-width UTC ISO-8601, so text order is time order.
                rows = try Row.fetchAll(
                    db, sql: "SELECT * FROM llm_usage WHERE createdAt >= ? ORDER BY createdAt, id",
                    arguments: [GRDBPlanRepository.timestamp(date)]
                )
            } else {
                rows = try Row.fetchAll(db, sql: "SELECT * FROM llm_usage ORDER BY createdAt, id")
            }
            return rows.compactMap(Self.record)
        }
    }

    public func clear() async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM llm_usage")
        }
    }

    public func firstRecordDate() async throws -> Date? {
        try await database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT MIN(createdAt) FROM llm_usage").flatMap(GRDBPlanRepository.date)
        }
    }

    /// Nil for a row this build cannot read (an unknown provider or purpose).
    private static func record(_ row: Row) -> LLMCallRecord? {
        guard
            let createdAt = GRDBPlanRepository.date(row["createdAt"]),
            let provider = LLMProvider(rawValue: row["provider"]),
            let purpose = LLMCallPurpose(rawValue: row["purpose"])
        else { return nil }
        return LLMCallRecord(
            id: row["id"],
            createdAt: createdAt,
            provider: provider,
            modelId: row["modelId"],
            purpose: purpose,
            success: row["success"],
            errorKind: row["errorKind"],
            usage: TokenUsage(
                uncachedInput: row["uncachedInput"],
                cacheRead: row["cacheRead"],
                cacheWrite: row["cacheWrite"],
                output: row["output"],
                reasoning: row["reasoning"]
            ),
            latencyMs: row["latencyMs"],
            costMicros: row["costMicros"],
            priceTableVersion: row["priceTableVersion"]
        )
    }
}
