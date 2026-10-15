import Foundation
import Testing
import Domain

struct HealthSectionsTests {
    @Test func workoutsSectionCountsBySourceAndTypeAndKeepsTenNewest() {
        var workouts = (0..<12).map { Fixture.workout(id: "run-\($0)", daysAgo: Double($0)) }
        workouts.append(Fixture.workout(id: "ride", type: .cycling, daysAgo: 0.5))

        let section = WorkoutsSection.summarizing(workouts)

        #expect(section.total == 13)
        #expect(section.bySource == ["Test": 13])
        #expect(section.byActivityType == ["running": 12, "cycling": 1])
        #expect(section.latest.count == 10)
        #expect(section.latest.prefix(3).map(\.id) == ["run-0", "ride", "run-1"])
    }

    @Test func restingHeartRateAveragesTheWindow() {
        let samples = [52.0, 54, 50].enumerated().map { index, value in
            HealthSample(value: value, unit: "bpm", date: Fixture.now.addingTimeInterval(-Double(index) * Fixture.day), sourceName: "Watch")
        }
        let section = RestingHeartRateSection.summarizing(windowSamples: samples, latestOverall: nil)
        #expect(section.average30Days == 52)
        #expect(section.sampleCount30Days == 3)
        #expect(section.latest?.value == 52)
        #expect(section.status == .ok)
    }

    @Test func restingHeartRateFallsBackToLatestOverall() {
        let old = HealthSample(value: 58, unit: "bpm", date: Fixture.now.addingTimeInterval(-60 * Fixture.day), sourceName: "Watch")
        let section = RestingHeartRateSection.summarizing(windowSamples: [], latestOverall: old)
        #expect(section.latest == old)
        #expect(section.average30Days == nil)
        #expect(section.sampleCount30Days == 0)
        #expect(section.status == .ok)
    }
}
