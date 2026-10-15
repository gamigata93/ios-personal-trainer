import Foundation
import Testing
import Domain

struct NormValidatorTests {
    private func table(
        id: String = "t", ageMin: Int = 20, ageMax: Int = 29,
        anchors: [(Double, Double)] = [(10, 1), (20, 2), (30, 3), (40, 4), (50, 5)]
    ) -> NormTable {
        NormTable(
            id: id, metric: .vo2max, sex: .male, ageMin: ageMin, ageMax: ageMax, unit: "u",
            anchors: anchors.map { NormAnchor(p: $0.0, v: $0.1) }, source: "s"
        )
    }

    private func validate(_ tables: [NormTable], version: Int = 1) throws(NormDataError) {
        try NormValidator.validate(NormDocument(schemaVersion: version, tables: tables))
    }

    @Test func acceptsAValidTable() throws {
        try validate([table()])
    }

    @Test func rejectsFewerThanFiveAnchors() {
        #expect(throws: NormDataError.self) { try validate([table(anchors: [(10, 1), (20, 2), (30, 3), (40, 4)])]) }
    }

    @Test func rejectsPercentilesThatDoNotIncrease() {
        #expect(throws: NormDataError.self) { try validate([table(anchors: [(10, 1), (20, 2), (20, 3), (40, 4), (50, 5)])]) }
    }

    @Test func rejectsDecreasingValues() {
        #expect(throws: NormDataError.self) { try validate([table(anchors: [(10, 1), (20, 3), (30, 2), (40, 4), (50, 5)])]) }
    }

    @Test func acceptsRepeatedValues() throws {
        try validate([table(anchors: [(10, 1), (20, 2), (30, 2), (40, 4), (50, 5)])])
    }

    @Test func rejectsNonPositiveValues() {
        #expect(throws: NormDataError.self) { try validate([table(anchors: [(10, 0), (20, 2), (30, 3), (40, 4), (50, 5)])]) }
    }

    @Test func rejectsInvertedAgeRange() {
        #expect(throws: NormDataError.self) { try validate([table(ageMin: 30, ageMax: 20)]) }
    }

    @Test func rejectsOverlappingAgeRanges() {
        #expect(throws: NormDataError.self) {
            try validate([table(id: "a", ageMin: 20, ageMax: 29), table(id: "b", ageMin: 29, ageMax: 39)])
        }
    }

    @Test func rejectsUnknownSchemaVersion() {
        #expect(throws: NormDataError.self) { try validate([table()], version: 2) }
    }
}
