#if DEBUG
import Foundation
import Domain

/// DEBUG only: the plan (with originalDate and isMissed per session) and its
/// recent edits as pretty JSON, for "Copy plan JSON".
public enum PlanDebugJSON {
    public static func string(plan: TrainingPlan, edits: [PlanEditRecord]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = Payload(plan: plan, edits: edits.map(Edit.init))
        return (try? encoder.encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private struct Payload: Encodable {
        let plan: TrainingPlan
        let edits: [Edit]

        func encode(to encoder: any Encoder) throws {
            // The plan's own keys at the top level, plus "edits".
            try plan.encode(to: encoder)
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(edits, forKey: .edits)
        }

        enum Key: String, CodingKey { case edits }
    }

    private struct Edit: Encodable {
        let id: Int64
        let createdAt: Date
        let kind: String
        let edit: PlanEdit
        let before: [SessionPlacement]
        let after: [SessionPlacement]
        let undoneAt: Date?

        init(_ record: PlanEditRecord) {
            id = record.id
            createdAt = record.createdAt
            kind = record.edit.kind
            edit = record.edit
            before = record.change.before
            after = record.change.after
            undoneAt = record.undoneAt
        }
    }
}
#endif
