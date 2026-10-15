import HealthKit
import Testing
@testable import Infrastructure

/// The one test that touches HealthKit types: it checks the adapter's mapping.
struct HealthKitActivityNamesTests {
    @Test(arguments: [
        (UInt(80), "cooldown"), (82, "swimBikeRun"), (83, "transition"), (84, "underwaterDiving"),
        (37, "running"), (13, "cycling"), (50, "traditionalStrengthTraining"),
    ])
    func namesTheNewerTypes(raw: UInt, name: String) throws {
        let type = try #require(HKWorkoutActivityType(rawValue: raw))
        #expect(HealthKitActivityNames.name(type) == name)
    }
}
