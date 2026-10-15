#if DEBUG
import Foundation
import Domain

/// DEBUG only: the usage ledger as pretty JSON for "Copy usage JSON". The ledger
/// holds token counts and costs only, so neither prompts, outputs nor the API key
/// can appear here.
public enum UsageLedgerJSON {
    public static func string(records: [LLMCallRecord], priceTableVersion: String?) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let payload = Payload(
            priceTableVersion: priceTableVersion,
            note: "Estimates from SDK-reported usage. Anthropic's Console is the source of truth.",
            totalCostMicros: records.reduce(0) { $0 + ($1.costMicros ?? 0) },
            records: records
        )
        return (try? encoder.encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Reads the whole ledger and encodes it.
    public static func export(ledger: any LLMUsageLedger, prices: any PriceTableProvider) async -> String? {
        guard let records = try? await ledger.records(since: nil) else { return nil }
        return string(records: records, priceTableVersion: prices.priceTable()?.version)
    }

    private struct Payload: Encodable {
        let priceTableVersion: String?
        let note: String
        let totalCostMicros: Int64
        let records: [LLMCallRecord]
    }
}
#endif
