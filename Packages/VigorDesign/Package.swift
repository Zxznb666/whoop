// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VigorDesign",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [.library(name: "VigorDesign", targets: ["VigorDesign"])],
    dependencies: [.package(path: "../VigorScoring")],
    targets: [
        .target(name: "VigorDesign", dependencies: ["VigorScoring"]),
        .testTarget(name: "VigorDesignTests", dependencies: ["VigorDesign", "VigorScoring"]),
    ]
)
