import Foundation
import Testing
import Domain

struct ProbitTests {
    @Test func medianIsZero() throws {
        #expect(abs(try #require(Probit.z(0.5))) < 1e-9)
    }

    @Test func oneSigma() throws {
        #expect(abs(try #require(Probit.z(0.8413447)) - 1.0) < 1e-3)
    }

    @Test func ninetySevenPointFive() throws {
        #expect(abs(try #require(Probit.z(0.975)) - 1.95996) < 1e-3)
    }

    @Test(arguments: [0.01, 0.1, 0.3, 0.02])
    func isSymmetric(p: Double) throws {
        #expect(abs(try #require(Probit.z(p)) + (try #require(Probit.z(1 - p)))) < 1e-9)
    }

    @Test(arguments: [0.0, 1.0, -0.1, 1.1])
    func rejectsOutOfRange(p: Double) {
        #expect(Probit.z(p) == nil)
    }
}
