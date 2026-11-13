// swift-tools-version: 6.2
// 只读调用 Vigor 的 VigorScoring / VigorHealth：导出合成快照与 Vigor 完整管线的逐周期结果，作为 Muse 参考实现的对照。
// 不修改 Packages/ 下的任何文件。
import PackageDescription

let package = Package(
    name: "VigorExport",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../../Packages/VigorScoring"),
        .package(path: "../../../Packages/VigorHealth"),
    ],
    targets: [
        .executableTarget(name: "vigor-export", dependencies: [
            .product(name: "VigorScoring", package: "VigorScoring"),
            .product(name: "VigorHealth", package: "VigorHealth"),
        ]),
    ]
)
