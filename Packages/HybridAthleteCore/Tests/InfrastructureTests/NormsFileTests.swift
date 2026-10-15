import Foundation
import Testing
import Domain
@testable import Infrastructure

struct NormsFileTests {
    private let repository = BundledNormRepository()

    private func value(_ metric: NormMetric, _ sex: NormSex, age: Int, p: Double) async throws -> Double? {
        let table = try #require(try await repository.table(metric: metric, sex: sex, ageYears: age))
        return table.anchors.first { $0.p == p }?.v
    }

    @Test func loadsAllTwentyNineTablesAndPassesValidation() async throws {
        let tables = try await repository.tables()
        #expect(tables.count == 29)
        #expect(tables.filter { $0.metric == .vo2max }.count == 14)
        #expect(tables.filter { $0.metric == .restingHeartRate }.count == 15)
        #expect(tables.allSatisfy { !$0.source.isEmpty })
    }

    @Test func spotChecksMatchThePublishedTables() async throws {
        #expect(try await value(.vo2max, .male, age: 35, p: 80) == 50.0)
        #expect(try await value(.vo2max, .female, age: 65, p: 10) == 13.4)
        #expect(try await value(.restingHeartRate, .male, age: 30, p: 50) == 69)
        #expect(try await value(.restingHeartRate, .female, age: 85, p: 97.5) == 98)
        #expect(try await value(.restingHeartRate, .all, age: 50, p: 25) == 62)
    }

    @Test func unpublishedAnchorsAreLeftOut() async throws {
        let table = try #require(try await repository.table(metric: .restingHeartRate, sex: .male, ageYears: 85))
        #expect(table.anchors.map(\.p) == [2.5, 5, 10, 25, 50, 75, 90, 95, 97.5])
        #expect(table.ageMax == 120)
    }

    @Test func sourcesNameTheirStudies() async throws {
        let vo2 = try #require(try await repository.table(metric: .vo2max, sex: .female, ageYears: 40))
        let resting = try #require(try await repository.table(metric: .restingHeartRate, sex: .all, ageYears: 40))
        #expect(vo2.source.hasPrefix("FRIEND registry, Kaminsky LA et al."))
        #expect(resting.source.hasPrefix("NHANES 1999-2008, Ostchega Y et al."))
    }

    @Test func malformedFileGivesTypedError() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("norms-\(UUID().uuidString).json")
        try Data("{ \"schemaVersion\": 1, \"tables\": [ { \"id\": 3 } ] }".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: NormDataError.malformed("Norms.json could not be decoded")) {
            _ = try await BundledNormRepository(url: url).tables()
        }
    }

    @Test func invalidTableGivesTypedError() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("norms-\(UUID().uuidString).json")
        let json = """
        { "schemaVersion": 1, "tables": [ { "id": "x", "metric": "vo2max", "sex": "male", "ageMin": 20,
          "ageMax": 29, "unit": "u", "source": "s", "anchors": [ {"p": 10, "v": 5}, {"p": 20, "v": 4},
          {"p": 30, "v": 6}, {"p": 40, "v": 7}, {"p": 50, "v": 8} ] } ] }
        """
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: NormDataError.malformed("x: values decrease")) {
            _ = try await BundledNormRepository(url: url).tables()
        }
    }

    @Test func missingFileGivesTypedError() async {
        await #expect(throws: NormDataError.missing) {
            _ = try await BundledNormRepository(url: nil).tables()
        }
    }

    @Test(arguments: [
        (19, nil), (20, "vo2max.male.20-29"), (39, "vo2max.male.30-39"), (40, "vo2max.male.40-49"),
        (79, "vo2max.male.70-79"), (80, "vo2max.male.80-89"), (89, "vo2max.male.80-89"), (90, nil),
    ] as [(Int, String?)])
    func vo2AgeBandBoundaries(age: Int, id: String?) async throws {
        #expect(try await repository.table(metric: .vo2max, sex: .male, ageYears: age)?.id == id)
    }

    @Test(arguments: [
        (15, nil), (16, "restingHeartRate.female.16-19"), (79, "restingHeartRate.female.60-79"),
        (80, "restingHeartRate.female.80+"), (120, "restingHeartRate.female.80+"),
    ] as [(Int, String?)])
    func restingAgeBandBoundaries(age: Int, id: String?) async throws {
        #expect(try await repository.table(metric: .restingHeartRate, sex: .female, ageYears: age)?.id == id)
    }

    @Test func coverageRanges() async throws {
        #expect(try await repository.coverage(metric: .vo2max, sex: .female) == 20...89)
        #expect(try await repository.coverage(metric: .vo2max, sex: .all) == nil)
        #expect(try await repository.coverage(metric: .restingHeartRate, sex: .all) == 16...120)
    }
}

/// The user's own reading (male, 32) through the real norm data.
struct RealDataPercentileTests {
    @Test func vo2MaxAboutEightySeven() async throws {
        let table = try #require(try await BundledNormRepository().table(metric: .vo2max, sex: .male, ageYears: 32))
        let result = try #require(PercentileCalculator.result(for: 53.75, in: table))
        // 80 + 10 x (53.75 - 50.0) / (55.5 - 50.0) = 86.82
        #expect(abs(result.betterThanPercent - 86.818) < 1e-3)
        #expect(result.betterThanPercent.rounded() == 87)
    }

    @Test func restingHeartRateAboutNinetyEight() async throws {
        let table = try #require(try await BundledNormRepository().table(metric: .restingHeartRate, sex: .male, ageYears: 32))
        let result = try #require(PercentileCalculator.result(for: 49, in: table))
        // P = 1 + 1.5 x (49 - 47) / (50 - 47) = 2.0 -> better than 98
        #expect(abs(result.betterThanPercent - 98) < 1e-9)
    }
}
