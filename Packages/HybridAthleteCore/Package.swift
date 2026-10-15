// swift-tools-version: 6.2
import PackageDescription

// Layers are separate targets so the compiler enforces the dependency direction:
// Domain <- Application <- Infrastructure. See CLAUDE.md before adding a dependency.
let package = Package(
    name: "HybridAthleteCore",
    // OS 27: ClaudeForFoundationModels requires it (strings, because the .v27
    // constants need tools-version 6.4).
    platforms: [.iOS("27.0"), .macOS("27.0"), .visionOS("27.0")],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Application", targets: ["Application"]),
        .library(name: "Infrastructure", targets: ["Infrastructure"]),
    ],
    dependencies: [
        // The database. Used only by Infrastructure/Persistence (CLAUDE.md).
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // Claude behind Apple's LanguageModel protocol (Apache-2.0, beta). Used only by Infrastructure/LLM.
        .package(url: "https://github.com/anthropics/ClaudeForFoundationModels.git", from: "0.1.0"),
    ],
    targets: [
        .target(name: "Domain"),
        .target(
            name: "Application",
            dependencies: ["Domain"],
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
        .target(
            name: "Infrastructure",
            dependencies: [
                "Application",
                "Domain",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ClaudeForFoundationModels", package: "ClaudeForFoundationModels"),
            ],
            resources: [.copy("Resources/Norms.json"), .copy("Resources/Prices.json")],
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "ApplicationTests", dependencies: ["Application", "Domain"]),
        // Adapter-level tests: the bundled norm data, personas and HealthKit name mapping.
        // GRDB only for the persistence tests' schema checks and forced failures.
        .testTarget(
            name: "InfrastructureTests",
            dependencies: [
                "Infrastructure",
                "Application",
                "Domain",
                .product(name: "GRDB", package: "GRDB.swift"),
                // Only for the Claude adapter tests (real package error values).
                .product(name: "ClaudeForFoundationModels", package: "ClaudeForFoundationModels"),
            ]
        ),
    ]
)
