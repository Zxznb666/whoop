// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VigorEngine",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [.library(name: "VigorEngine", targets: ["VigorEngine"])],
    dependencies: [
        .package(path: "../VigorScoring"),
        .package(path: "../VigorHealth"),
        .package(path: "../VigorStore"),
    ],
    targets: [
        .target(name: "VigorEngine", dependencies: [
            "VigorScoring",
            "VigorHealth",
            "VigorStore",
        ]),
        .testTarget(name: "VigorEngineTests", dependencies: ["VigorEngine", "VigorScoring", "VigorHealth", "VigorStore"]),
    ]
)
