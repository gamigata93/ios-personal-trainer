import Foundation

/// Checks norm tables before they are used, so a bad file fails loudly at load
/// instead of producing a wrong percentile.
public enum NormValidator {
    public static let supportedSchemaVersion = 1
    public static let minimumAnchors = 5

    public static func validate(_ document: NormDocument) throws(NormDataError) {
        guard document.schemaVersion == supportedSchemaVersion else {
            throw .malformed("Unsupported schemaVersion \(document.schemaVersion)")
        }
        for table in document.tables {
            try validate(table)
        }
        try checkNoOverlaps(document.tables)
    }

    private static func validate(_ table: NormTable) throws(NormDataError) {
        guard table.ageMin <= table.ageMax else {
            throw .malformed("\(table.id): ageMin is greater than ageMax")
        }
        guard table.anchors.count >= minimumAnchors else {
            throw .malformed("\(table.id): fewer than \(minimumAnchors) anchors")
        }
        guard !table.source.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw .malformed("\(table.id): missing source")
        }
        for anchor in table.anchors where !(anchor.v > 0) || !(0...100).contains(anchor.p) {
            throw .malformed("\(table.id): anchor p \(anchor.p) v \(anchor.v) is out of range")
        }
        for (previous, next) in zip(table.anchors, table.anchors.dropFirst()) {
            guard next.p > previous.p else {
                throw .malformed("\(table.id): percentiles are not strictly increasing")
            }
            guard next.v >= previous.v else {
                throw .malformed("\(table.id): values decrease")
            }
        }
    }

    private static func checkNoOverlaps(_ tables: [NormTable]) throws(NormDataError) {
        let groups = Dictionary(grouping: tables) { "\($0.metric.rawValue).\($0.sex.rawValue)" }
        for (group, members) in groups {
            let sorted = members.sorted { $0.ageMin < $1.ageMin }
            for (previous, next) in zip(sorted, sorted.dropFirst()) where next.ageMin <= previous.ageMax {
                throw .malformed("\(group): age ranges \(previous.id) and \(next.id) overlap")
            }
        }
    }
}
