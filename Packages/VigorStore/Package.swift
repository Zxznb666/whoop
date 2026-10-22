// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VigorStore",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [.library(name: "VigorStore", targets: ["VigorStore"])],
    dependencies: [.package(path: "../VigorScoring"), .package(path: "../VigorFIT")],
    targets: [
        .target(name: "VigorStore", dependencies: ["VigorScoring", "VigorFIT"]),
        .testTarget(name: "VigorStoreTests", dependencies: ["VigorStore", "VigorScoring", "VigorFIT"]),
    ]
)
