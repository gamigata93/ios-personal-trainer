#if DEBUG
import Foundation
import Domain

/// DEBUG only: "Copy analysis JSON" and "Copy note JSON" on Session detail. The
/// analysis holds no coordinates or sample timestamps; the note holds no prompt.
public enum WorkoutNoteDebugJSON {
    public static func analysis(_ analysis: WorkoutAnalysis) -> String? {
        encode(analysis)
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
