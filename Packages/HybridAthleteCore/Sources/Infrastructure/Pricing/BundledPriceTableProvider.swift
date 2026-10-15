import Foundation
import Application
import Domain

/// The Prices.json shipped in this package's resources, decoded once. A missing
/// or malformed file gives nil, and Claude runs are blocked ("Price table unavailable").
public struct BundledPriceTableProvider: PriceTableProvider {
    private let table: PriceTable?

    public init() {
        self.init(url: Bundle.module.url(forResource: "Prices", withExtension: "json"))
    }

    /// Loads from a specific file. Used by tests.
    public init(url: URL?) {
        table = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? PriceTable.decode($0) }
    }

    public func priceTable() -> PriceTable? { table }
}
