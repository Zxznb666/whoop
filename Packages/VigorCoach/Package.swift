// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VigorCoach",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [.library(name: "VigorCoach", targets: ["VigorCoach"])],
    dependencies: [.package(path: "../VigorScoring")],
    targets: [
        .target(name: "VigorCoach", dependencies: ["VigorScoring"]),
        .testTarget(name: "VigorCoachTests", dependencies: ["VigorCoach", "VigorScoring"]),
    ]
)
