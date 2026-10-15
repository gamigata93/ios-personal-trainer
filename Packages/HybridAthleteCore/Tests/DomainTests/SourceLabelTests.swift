import Testing
import Domain

struct SourceLabelTests {
    @Test(arguments: [
        ("Georgi's Apple Watch", "Apple Watch"),
        ("Georgi’s Apple Watch", "Apple Watch"),
        ("Anna Maria's iPhone", "iPhone"),
        ("Sam’s iPad", "iPad"),
    ])
    func removesPersonalNames(input: String, expected: String) {
        #expect(SourceLabel.normalize(input) == expected)
    }

    @Test(arguments: ["WorkOutDoors", "Kinomap", "Zepp", "Fitness", "Apple Watch", "'s Apple Watch"])
    func leavesOtherNamesUnchanged(name: String) {
        #expect(SourceLabel.normalize(name) == name)
    }
}
