import Foundation
import Application
import Domain

/// Reference tables from the Norms.json bundled with the app. Loaded and
/// validated once, then cached. A missing or malformed file throws
/// `NormDataError` on every call; the app hides the scales instead of crashing.
public actor BundledNormRepository: NormRepository {
    private let url: URL?
    private var cached: Result<[NormTable], NormDataError>?

    /// Uses the Norms.json shipped in this package's resources.
    public init() {
        self.url = Bundle.module.url(forResource: "Norms", withExtension: "json")
    }

    /// Loads from a specific file. Used by tests.
    public init(url: URL?) {
        self.url = url
    }

    public func table(metric: NormMetric, sex: NormSex, ageYears: Int) async throws -> NormTable? {
        NormLookup.table(in: try tables(), metric: metric, sex: sex, ageYears: ageYears)
    }

    public func coverage(metric: NormMetric, sex: NormSex) async throws -> ClosedRange<Int>? {
        NormLookup.coverage(in: try tables(), metric: metric, sex: sex)
    }

    /// All tables, after validation.
    public func tables() throws(NormDataError) -> [NormTable] {
        if let cached { return try cached.get() }
        let result = Self.load(url)
        cached = result
        return try result.get()
    }

    private static func load(_ url: URL?) -> Result<[NormTable], NormDataError> {
        guard let url, let data = try? Data(contentsOf: url) else { return .failure(.missing) }
        do {
            let document = try JSONDecoder().decode(NormDocument.self, from: data)
            try NormValidator.validate(document)
            return .success(document.tables)
        } catch let error as NormDataError {
            return .failure(error)
        } catch {
            return .failure(.malformed("Norms.json could not be decoded"))
        }
    }
}
