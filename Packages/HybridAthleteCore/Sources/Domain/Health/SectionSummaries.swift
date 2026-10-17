import Foundation

/// Characteristics as summaries: age only, never the date of birth.
public struct ProfileSummary: Sendable, Equatable, Codable {
    public let ageYears: Int?
    public let biologicalSex: BiologicalSex?

    public init(ageYears: Int?, biologicalSex: BiologicalSex?) {
        self.ageYears = ageYears
        self.biologicalSex = biologicalSex
    }
}

public struct VO2MaxSummary: Sendable, Equatable, Codable {
    public let latest: HealthSample
    /// Newest first.
    public let recent: [HealthSample]

    public init(latest: HealthSample, recent: [HealthSample]) {
        self.latest = latest
        self.recent = recent
    }
}

public struct RestingHeartRateSummary: Sendable, Equatable, Codable {
    public let latest: HealthSample
    public let average30Days: Double?
    public let sampleCount30Days: Int

    public init(latest: HealthSample, average30Days: Double?, sampleCount30Days: Int) {
        self.latest = latest
        self.average30Days = average30Days
        self.sampleCount30Days = sampleCount30Days
    }
}

/// Everything the app keeps from the workout list: counts and derived numbers,
/// never the workouts themselves.
public struct WorkoutsSummary: Sendable, Equatable, Codable {
    public let totalCount: Int
    /// Running workouts in the 28-day volume window.
    public let runCount: Int
    public let runHeartRateAverage: Double?
    public let personalRecords: [PersonalRecord]
    public let volume: RunningVolume
    /// The highest max heart rate of the last 365 days' runs, when at least 3
    /// runs have heart rate (`ObservedMaxHeartRate`).
    public let observedMaxHr: Double?

    public init(
        totalCount: Int,
        runCount: Int,
        runHeartRateAverage: Double?,
        personalRecords: [PersonalRecord],
        volume: RunningVolume,
        observedMaxHr: Double? = nil
    ) {
        self.totalCount = totalCount
        self.runCount = runCount
        self.runHeartRateAverage = runHeartRateAverage
        self.personalRecords = personalRecords
        self.volume = volume
        self.observedMaxHr = observedMaxHr
    }

    /// Derives the summary from the full workout list and the sections computed from it.
    public static func summarizing(
        _ workouts: WorkoutsSection,
        runHeartRate: RunHeartRateSection,
        personalRecords: PersonalRecordsSection,
        now: Date
    ) -> WorkoutsSummary {
        let windowStart = now.addingTimeInterval(-TimeInterval(PlanFitRules.volumeWindowDays) * 86_400)
        return WorkoutsSummary(
            totalCount: workouts.total,
            runCount: workouts.all.filter { $0.isRun && $0.start >= windowStart && $0.start <= now }.count,
            runHeartRateAverage: runHeartRate.averageBpm,
            personalRecords: personalRecords.items,
            volume: RunningVolume.measure(workouts.all, now: now),
            observedMaxHr: ObservedMaxHeartRate.value(workouts: workouts.all, now: now)
        )
    }
}
