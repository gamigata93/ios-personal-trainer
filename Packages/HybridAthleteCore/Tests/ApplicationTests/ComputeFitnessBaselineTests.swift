import Foundation
import Testing
import Application
import Domain

struct ComputeFitnessBaselineTests {
    /// One table per metric and sex covering every age, or failing every call.
    private struct FakeNorms: NormRepository {
        var fails = false

        func table(metric: NormMetric, sex: NormSex, ageYears: Int) async throws -> NormTable? {
            if fails { throw NormDataError.missing }
            let anchors = (1...9).map { NormAnchor(p: Double($0 * 10), v: Double(30 + $0 * 3)) }
            return NormTable(
                id: "\(metric.rawValue).\(sex.rawValue)", metric: metric, sex: sex, ageMin: 0, ageMax: 120,
                unit: "u", anchors: anchors, source: "fake"
            )
        }

        func coverage(metric: NormMetric, sex: NormSex) async throws -> ClosedRange<Int>? {
            if fails { throw NormDataError.missing }
            if metric == .vo2max && sex == .all { return nil }
            return metric == .vo2max ? 20...89 : 16...120
        }
    }

    private let vo2 = VO2MaxSummary(latest: FakeHealthDataSource.sample(45, unit: "ml/(kg·min)"), recent: [])
    private let resting = RestingHeartRateSummary(latest: FakeHealthDataSource.sample(50, unit: "bpm"), average30Days: 50, sampleCount30Days: 1)

    private func baseline(_ norms: FakeNorms = FakeNorms()) -> ComputeFitnessBaseline {
        ComputeFitnessBaseline(norms: norms, clock: FakeClock(FakeHealthDataSource.now))
    }

    @Test func unknownAgeHidesBothScales() async {
        let profile = ProfileSummary(ageYears: nil, biologicalSex: .male)
        #expect(await baseline().vo2Max(vo2, profile: profile).norm == .unavailable(.ageUnknown))
        #expect(await baseline().restingHeartRate(resting, profile: profile).norm == .unavailable(.ageUnknown))
    }

    @Test func noProfileAtAllIsAgeUnknown() async {
        #expect(await baseline().vo2Max(vo2, profile: nil).norm == .unavailable(.ageUnknown))
    }

    @Test(arguments: [BiologicalSex.other, .notSet])
    func sexNotSetFallsBackForRestingHeartRateOnly(sex: BiologicalSex) async {
        let profile = ProfileSummary(ageYears: 30, biologicalSex: sex)
        #expect(await baseline().vo2Max(vo2, profile: profile).norm == .unavailable(.sexNotSet))
        guard case .compared(let comparison) = await baseline().restingHeartRate(resting, profile: profile).norm else {
            Issue.record("resting heart rate should be compared")
            return
        }
        #expect(comparison.population == .allAdults)
        #expect(comparison.tableId == "restingHeartRate.all")
    }

    @Test func ageOutsideCoverageNamesTheLimit() async {
        #expect(await baseline().vo2Max(vo2, profile: ProfileSummary(ageYears: 17, biologicalSex: .female)).norm == .unavailable(.belowMinimumAge(20)))
        #expect(await baseline().vo2Max(vo2, profile: ProfileSummary(ageYears: 91, biologicalSex: .female)).norm == .unavailable(.aboveMaximumAge(89)))
        #expect(await baseline().restingHeartRate(resting, profile: ProfileSummary(ageYears: 15, biologicalSex: .female)).norm == .unavailable(.belowMinimumAge(16)))
    }

    @Test func missingValuesHaveNoComparison() async {
        #expect(await baseline().vo2Max(nil, profile: nil) == MetricBaseline(reading: nil, norm: nil))
    }

    @Test func brokenNormDataHidesScalesWithoutFailing() async {
        let result = await baseline(FakeNorms(fails: true)).vo2Max(vo2, profile: ProfileSummary(ageYears: 30, biologicalSex: .male))
        #expect(result.norm == .unavailable(.normsUnavailable))
        #expect(result.reading?.value == 45)
    }

    @Test func recordsGetOneRowPerDistance() {
        let record = PersonalRecord(
            distance: .tenK, timeSeconds: 2_700, actualDistanceMeters: 10_000, timeIsNormalized: false,
            date: FakeHealthDataSource.now, workoutId: "w", isNew: true
        )
        let workouts = WorkoutsSummary(totalCount: 1, runCount: 1, runHeartRateAverage: nil, personalRecords: [record], volume: .none)
        let rows = baseline().records(workouts)
        #expect(rows.map(\.distance) == [.fiveK, .tenK, .halfMarathon])
        #expect(rows[1].record?.record == record)
        #expect(rows[0].record == nil)
    }
}
