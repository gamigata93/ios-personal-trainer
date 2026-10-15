import Foundation

/// Picks the table for a metric, sex and age from a validated set.
public enum NormLookup {
    public static func table(in tables: [NormTable], metric: NormMetric, sex: NormSex, ageYears: Int) -> NormTable? {
        tables.first { $0.metric == metric && $0.sex == sex && $0.covers(age: ageYears) }
    }

    /// The ages the tables for a metric and sex cover, or `nil` when there are none.
    public static func coverage(in tables: [NormTable], metric: NormMetric, sex: NormSex) -> ClosedRange<Int>? {
        let matching = tables.filter { $0.metric == metric && $0.sex == sex }
        guard let lower = matching.map(\.ageMin).min(), let upper = matching.map(\.ageMax).max() else { return nil }
        return lower...upper
    }
}
