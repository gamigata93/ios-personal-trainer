import Foundation

/// The recovery around one run: the sleep night and HRV night woken on the run's
/// local date, and the resting heart rate of that day (otherwise the day
/// before). Each compared with its 7 previous values; each nil when missing.
public enum RecoveryContext {
    public static func facts(
        runDate: LocalDate, sleepNights: [SleepNight], hrvNights: [HRVNight], restingDays: [RestingHRDay]
    ) -> RecoveryFacts {
        RecoveryFacts(
            sleep: sleep(runDate: runDate, nights: sleepNights),
            hrv: hrv(runDate: runDate, nights: hrvNights),
            restingHr: resting(runDate: runDate, days: restingDays)
        )
    }

    static func sleep(runDate: LocalDate, nights: [SleepNight]) -> SleepFact? {
        guard let night = nights.first(where: { $0.wakeDate == runDate }) else { return nil }
        let comparison = SleepComparison.make(shown: night, nights: nights)
        return SleepFact(
            asleepMinutes: night.asleepMinutes,
            deltaPercent: comparison?.deltaPercent,
            nightsUsed: comparison?.nightsUsed ?? SleepRules.baselineNights
        )
    }

    static func hrv(runDate: LocalDate, nights: [HRVNight]) -> HRVFact? {
        guard let night = nights.first(where: { $0.wakeDate == runDate }) else { return nil }
        let previous = MetricComparison.previous(nights, date: \.wakeDate, before: night.wakeDate, days: RecoveryRules.baselineWindow)
        let comparison = MetricComparison.make(
            shown: night.meanMs, previous: previous.map(\.meanMs), mode: .percent,
            neutralBand: RecoveryRules.hrvNeutralPercent, direction: .higherIsBetter, minValues: RecoveryRules.minBaselineValues
        )
        return HRVFact(valueMs: night.meanMs, deltaPercent: comparison?.delta, nightsUsed: comparison?.countUsed ?? RecoveryRules.baselineWindow)
    }

    static func resting(runDate: LocalDate, days: [RestingHRDay]) -> RestingHRFact? {
        guard let day = days.first(where: { $0.date == runDate }) ?? days.first(where: { $0.date == runDate.adding(days: -1) }) else {
            return nil
        }
        let previous = MetricComparison.previous(days, date: \.date, before: day.date, days: RecoveryRules.baselineWindow)
        let comparison = MetricComparison.make(
            shown: day.bpm, previous: previous.map(\.bpm), mode: .absolute,
            neutralBand: RecoveryRules.restingHRNeutralBpm, direction: .lowerIsBetter, minValues: RecoveryRules.minBaselineValues
        )
        return RestingHRFact(bpm: day.bpm, deltaBpm: comparison?.delta, daysUsed: comparison?.countUsed ?? RecoveryRules.baselineWindow)
    }
}
