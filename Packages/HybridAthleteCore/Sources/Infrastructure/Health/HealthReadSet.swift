import Foundation
import HealthKit
import Application
import Domain

/// Every HealthKit type the app reads, requested together in one sheet. The
/// single source of truth: when you add a read type, add it here. Adding one
/// makes existing installs see the Connect screen once more.
enum HealthReadSet {
    static var types: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.vo2Max),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),
            // Workout analysis: cadence comes from step counts (cadence is not a
            // Health type), plus running power and Apple's effort scores.
            HKQuantityType(.stepCount),
            HKQuantityType(.runningPower),
            HKQuantityType(.workoutEffortScore),
            HKQuantityType(.estimatedWorkoutEffortScore),
        ]
    }
}

/// Translates HealthKit errors into `HealthDataError` at the boundary.
func translatingHealthKitErrors<T>(_ body: () async throws -> T) async throws(HealthDataError) -> T {
    do {
        return try await body()
    } catch let error as HKError {
        switch error.code {
        case .errorDatabaseInaccessible: throw .locked
        case .errorAuthorizationDenied, .errorAuthorizationNotDetermined: throw .notAllowed
        case .errorHealthDataUnavailable, .errorHealthDataRestricted: throw .unavailable
        default: throw .failed
        }
    } catch let error as HealthDataError {
        throw error
    } catch {
        throw .failed
    }
}
