// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VigorHealth",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [.library(name: "VigorHealth", targets: ["VigorHealth"])],
    dependencies: [.package(path: "../VigorScoring"), .package(path: "../VigorFIT")],
    targets: [
        .target(name: "VigorHealth", dependencies: ["VigorScoring", "VigorFIT"]),
        .testTarget(name: "VigorHealthTests", dependencies: ["VigorHealth", "VigorScoring", "VigorFIT"]),
    ]
)
