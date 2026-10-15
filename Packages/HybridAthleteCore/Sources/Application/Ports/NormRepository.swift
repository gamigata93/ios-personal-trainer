import Foundation
import Domain

/// Read-only reference data for comparing a value with a population.
/// Implementations throw `NormDataError` when the data cannot be used.
public protocol NormRepository: Sendable {
    func table(metric: NormMetric, sex: NormSex, ageYears: Int) async throws -> NormTable?
    /// The ages covered for a metric and sex, or `nil` when there are no tables for that sex.
    func coverage(metric: NormMetric, sex: NormSex) async throws -> ClosedRange<Int>?
}
