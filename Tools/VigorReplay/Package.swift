// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VigorReplay",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "vigor-replay", targets: ["vigor-replay"])],
    dependencies: [
        .package(path: "../../Packages/VigorScoring"),
        .package(path: "../../Packages/VigorHealth"),
    ],
    targets: [
        .target(name: "VigorReplayCore", dependencies: [
            .product(name: "VigorScoring", package: "VigorScoring"),
            .product(name: "VigorHealth", package: "VigorHealth"),
        ]),
        .executableTarget(name: "vigor-replay", dependencies: ["VigorReplayCore"]),
        .testTarget(name: "VigorReplayCoreTests", dependencies: [
            "VigorReplayCore",
            .product(name: "VigorScoring", package: "VigorScoring"),
            .product(name: "VigorHealth", package: "VigorHealth"),
        ], resources: [.copy("Resources/golden-synthetic-seed42.csv")]),
    ]
)
