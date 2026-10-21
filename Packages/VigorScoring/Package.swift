// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VigorScoring",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [.library(name: "VigorScoring", targets: ["VigorScoring"])],
    dependencies: [.package(path: "../VigorFIT")],
    targets: [
        .target(name: "VigorScoring", dependencies: ["VigorFIT"]),
        .testTarget(name: "VigorScoringTests", dependencies: ["VigorScoring", "VigorFIT"]),
    ]
)
