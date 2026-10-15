import Foundation
import Domain

/// One finished part of the health read, delivered as soon as it is ready.
public enum HealthReadUpdate: Sendable, Equatable {
    case profile(ProfileSection)
    case vo2Max(VO2MaxSection)
    case restingHeartRate(RestingHeartRateSection)
    case workouts(WorkoutsSection)
    case runHeartRate(RunHeartRateSection)
    case personalRecords(PersonalRecordsSection)
    /// Always the last update, once every section has reported.
    case finished(HealthSnapshot)
}

/// Reads the fitness baseline from the health store. Sections run in parallel
/// and fail independently, so one locked or empty section never blocks the rest.
public struct ReadHealthBaseline: Sendable {
    public static let vo2MaxRecentLimit = 10

    private let health: any HealthDataSource
    private let clock: any Clock

    public init(health: any HealthDataSource, clock: any Clock) {
        self.health = health
        self.clock = clock
    }

    public func execute() -> AsyncStream<HealthReadUpdate> {
        AsyncStream { continuation in
            let task = Task {
                let now = clock.now()
                async let profile = readProfile(reportingTo: continuation)
                async let vo2Max = readVO2Max(reportingTo: continuation)
                async let restingHeartRate = readRestingHeartRate(now: now, reportingTo: continuation)
                async let workoutSections = readWorkouts(now: now, reportingTo: continuation)

                let (workouts, runHeartRate, personalRecords) = await workoutSections
                let snapshot = HealthSnapshot(
                    generatedAt: clock.now(),
                    profile: await profile,
                    vo2Max: await vo2Max,
                    restingHeartRate: await restingHeartRate,
                    runHeartRate: runHeartRate,
                    workouts: workouts,
                    personalRecords: personalRecords
                )
                continuation.yield(.finished(snapshot))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Sections

    private typealias Continuation = AsyncStream<HealthReadUpdate>.Continuation

    private func readProfile(reportingTo continuation: Continuation) async -> ProfileSection {
        let section: ProfileSection
        do {
            let profile = try await health.readProfile()
            section = ProfileSection(
                status: profile.isEmpty ? .emptyOrNotAllowed : .ok,
                ageYears: profile.ageYears,
                biologicalSex: profile.biologicalSex
            )
        } catch {
            section = .unread(ReadStatus(error))
        }
        continuation.yield(.profile(section))
        return section
    }

    private func readVO2Max(reportingTo continuation: Continuation) async -> VO2MaxSection {
        let section: VO2MaxSection
        do {
            let recent = try await health.readSamples(.vo2Max, since: nil, limit: Self.vo2MaxRecentLimit)
            section = VO2MaxSection(status: recent.isEmpty ? .emptyOrNotAllowed : .ok, latest: recent.first, recent: recent)
        } catch {
            section = .unread(ReadStatus(error))
        }
        continuation.yield(.vo2Max(section))
        return section
    }

    private func readRestingHeartRate(now: Date, reportingTo continuation: Continuation) async -> RestingHeartRateSection {
        let section: RestingHeartRateSection
        do {
            let windowStart = now.addingTimeInterval(-TimeInterval(RestingHeartRateSection.windowDays) * 86_400)
            let window = try await health.readSamples(.restingHeartRate, since: windowStart, limit: nil)
            // Fall back to the newest sample ever only when the window is empty.
            let latestOverall = window.isEmpty
                ? try await health.readSamples(.restingHeartRate, since: nil, limit: 1).first
                : nil
            section = .summarizing(windowSamples: window, latestOverall: latestOverall)
        } catch {
            section = .unread(ReadStatus(error))
        }
        continuation.yield(.restingHeartRate(section))
        return section
    }

    private func readWorkouts(
        now: Date,
        reportingTo continuation: Continuation
    ) async -> (WorkoutsSection, RunHeartRateSection, PersonalRecordsSection) {
        let workouts: WorkoutsSection
        let runHeartRate: RunHeartRateSection
        let personalRecords: PersonalRecordsSection
        do {
            let all = try await health.readWorkouts(routeCheckLimit: WorkoutsSection.latestCount)
            workouts = .summarizing(all)
            if all.isEmpty {
                runHeartRate = .unread(.emptyOrNotAllowed)
                personalRecords = .unread(.emptyOrNotAllowed)
            } else {
                runHeartRate = RunHeartRateAverage.section(for: all, now: now)
                let runsHaveDistance = all.contains { $0.isRun && $0.distanceMeters != nil }
                personalRecords = PersonalRecordsSection(
                    status: runsHaveDistance ? .ok : .emptyOrNotAllowed,
                    items: PersonalRecordDetector.records(in: all, now: now)
                )
            }
        } catch {
            let status = ReadStatus(error)
            workouts = .unread(status)
            runHeartRate = .unread(status)
            personalRecords = .unread(status)
        }
        continuation.yield(.workouts(workouts))
        continuation.yield(.runHeartRate(runHeartRate))
        continuation.yield(.personalRecords(personalRecords))
        return (workouts, runHeartRate, personalRecords)
    }
}
