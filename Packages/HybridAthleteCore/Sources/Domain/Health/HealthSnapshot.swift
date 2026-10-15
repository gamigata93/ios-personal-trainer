import Foundation

/// Everything read from Apple Health in one pass.
public struct HealthSnapshot: Sendable, Equatable {
    public let generatedAt: Date
    public let profile: ProfileSection
    public let vo2Max: VO2MaxSection
    public let restingHeartRate: RestingHeartRateSection
    public let runHeartRate: RunHeartRateSection
    public let workouts: WorkoutsSection
    public let personalRecords: PersonalRecordsSection

    public init(
        generatedAt: Date,
        profile: ProfileSection,
        vo2Max: VO2MaxSection,
        restingHeartRate: RestingHeartRateSection,
        runHeartRate: RunHeartRateSection,
        workouts: WorkoutsSection,
        personalRecords: PersonalRecordsSection
    ) {
        self.generatedAt = generatedAt
        self.profile = profile
        self.vo2Max = vo2Max
        self.restingHeartRate = restingHeartRate
        self.runHeartRate = runHeartRate
        self.workouts = workouts
        self.personalRecords = personalRecords
    }
}
