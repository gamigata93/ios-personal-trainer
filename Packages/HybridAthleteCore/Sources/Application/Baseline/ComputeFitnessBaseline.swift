import Foundation
import Domain

/// Turns section summaries into the starting-point numbers: percentile
/// comparisons and personal-record display flags.
public struct ComputeFitnessBaseline: Sendable {
    private let norms: any NormRepository
    private let clock: any Clock

    public init(norms: any NormRepository, clock: any Clock) {
        self.norms = norms
        self.clock = clock
    }

    public func vo2Max(_ summary: VO2MaxSummary?, profile: ProfileSummary?) async -> MetricBaseline {
        guard let latest = summary?.latest else { return MetricBaseline(reading: nil, norm: nil) }
        let norm = await compare(
            latest.value,
            metric: .vo2max,
            population: Self.vo2Population(profile?.biologicalSex),
            age: profile?.ageYears
        )
        return MetricBaseline(reading: MetricReading(value: latest.value, date: latest.date), norm: norm)
    }

    public func restingHeartRate(_ summary: RestingHeartRateSummary?, profile: ProfileSummary?) async -> MetricBaseline {
        guard let latest = summary?.latest else { return MetricBaseline(reading: nil, norm: nil) }
        let norm = await compare(
            latest.value,
            metric: .restingHeartRate,
            population: Self.restingPopulation(profile?.biologicalSex),
            age: profile?.ageYears
        )
        return MetricBaseline(reading: MetricReading(value: latest.value, date: latest.date), norm: norm)
    }

    /// One row per record distance, with display flags as of now.
    public func records(_ workouts: WorkoutsSummary) -> [PersonalRecordRow] {
        let now = clock.now()
        return RecordDistance.allCases.map { distance in
            PersonalRecordRow(
                distance: distance,
                record: workouts.personalRecords
                    .first { $0.distance == distance }
                    .map { PersonalRecordDisplay(record: $0, now: now) }
            )
        }
    }

    // MARK: Norms

    /// VO2 max norms exist only for male and female.
    private static func vo2Population(_ sex: BiologicalSex?) -> (NormSex, NormPopulation)? {
        switch sex {
        case .male: (.male, .ageAndSex)
        case .female: (.female, .ageAndSex)
        case .other, .notSet, nil: nil
        }
    }

    /// Resting heart rate falls back to the all-adults tables when sex is not set.
    private static func restingPopulation(_ sex: BiologicalSex?) -> (NormSex, NormPopulation)? {
        switch sex {
        case .male: (.male, .ageAndSex)
        case .female: (.female, .ageAndSex)
        case .other, .notSet, nil: (.all, .allAdults)
        }
    }

    private func compare(
        _ value: Double,
        metric: NormMetric,
        population: (NormSex, NormPopulation)?,
        age: Int?
    ) async -> NormOutcome {
        guard let age else { return .unavailable(.ageUnknown) }
        guard let (sex, group) = population else { return .unavailable(.sexNotSet) }
        do {
            guard let coverage = try await norms.coverage(metric: metric, sex: sex) else {
                return .unavailable(.sexNotSet)
            }
            if age < coverage.lowerBound { return .unavailable(.belowMinimumAge(coverage.lowerBound)) }
            if age > coverage.upperBound { return .unavailable(.aboveMaximumAge(coverage.upperBound)) }
            guard
                let table = try await norms.table(metric: metric, sex: sex, ageYears: age),
                let result = PercentileCalculator.result(for: value, in: table)
            else {
                return .unavailable(.normsUnavailable)
            }
            return .compared(NormComparison(result: result, population: group, tableId: table.id, source: table.source))
        } catch {
            return .unavailable(.normsUnavailable)
        }
    }
}
