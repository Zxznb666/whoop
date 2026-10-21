// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VigorFIT",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [.library(name: "VigorFIT", targets: ["VigorFIT"])],
    targets: [
        .target(name: "VigorFIT"),
        .testTarget(name: "VigorFITTests", dependencies: ["VigorFIT"]),
    ]
)
