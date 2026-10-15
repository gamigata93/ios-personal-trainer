import Foundation
import Domain

/// Turns one model attempt into a ledger record (with its estimated cost for
/// Claude) and hands it to the recorder. Adapters call this once per attempt they
/// send, success or failure, so retries are counted one by one. The Application
/// decorators never record.
public struct LLMCallMeter: Sendable {
    private let prices: any PriceTableProvider
    private let recorder: any LLMCallRecorder
    private let clock: any Clock

    public init(prices: any PriceTableProvider, recorder: any LLMCallRecorder, clock: any Clock) {
        self.prices = prices
        self.recorder = recorder
        self.clock = clock
    }

    /// Records the attempt and returns what was stored (its cost included).
    @discardableResult
    public func record(model: ModelChoice, purpose: LLMCallPurpose, usage: TokenUsage, latencyMs: Int, error: LLMError?) async -> LLMCallRecord {
        let table = prices.priceTable()
        let cost: Int64? = model.provider == .anthropic
            ? table.flatMap { CostCalculator.cost(usage, modelApiId: model.ledgerModelId, table: $0)?.total }
            : nil
        let record = LLMCallRecord(
            createdAt: clock.now(),
            provider: model.provider,
            modelId: model.ledgerModelId,
            purpose: purpose,
            success: error == nil,
            errorKind: error?.kind,
            usage: usage,
            latencyMs: latencyMs,
            costMicros: cost,
            priceTableVersion: table?.version ?? "none"
        )
        await recorder.record(record)
        return record
    }
}
