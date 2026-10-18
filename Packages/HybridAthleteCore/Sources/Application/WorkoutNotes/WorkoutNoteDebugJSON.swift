#if DEBUG
import Foundation
import Domain

/// DEBUG only: "Copy analysis JSON" and "Copy note JSON" on Session detail. The
/// analysis holds no coordinates or sample timestamps; the note holds no prompt.
public enum WorkoutNoteDebugJSON {
    /// The analysis plus the flatSeries diagnostic.
    public static func analysis(_ analysis: WorkoutAnalysis) -> String? {
        encode(AnalysisWithDiagnostics(analysis: analysis, flatSeries: analysis.flatSeries))
    }

    private struct AnalysisWithDiagnostics: Encodable {
        let analysis: WorkoutAnalysis
        let flatSeries: Bool

        func encode(to encoder: any Encoder) throws {
            try analysis.encode(to: encoder)
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(flatSeries, forKey: .flatSeries)
        }

        private enum Key: String, CodingKey { case flatSeries }
    }

    public static func note(_ note: SavedCoachNote) -> String? {
        encode(note)
    }

    private static func encode(_ value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
#endif
