# 施工任务：元气 Vigor · M0（工程骨架 + HRV 数据可行性验证）

你是一名资深 iOS 工程师，在 `/Users/zxz/Vibecoding/whoop` 中实现 M0 里程碑。请**严格按本文档执行**，不要扩展范围。遇到本文没写清楚的地方，选最简单、可逆的做法，并在最终报告中写明。

---

## 0. 必读

1. 先通读 `docs/PRD.md`，重点读 §2（数据可行性）、§3.1（生理周期）、§5.2（夜间 HRV）、§5.3（夜间静息心率）、§8（技术架构）。
2. 本次 M0 **只做**：工程骨架、HealthKit 读取、数据快照导出/回放、夜间 HRV 与静息心率的计算、“实验室”页面，以及**用企业证书签名导出可安装的 IPA**。
3. **不做**：恢复分数、负荷、睡眠需求、基线、SwiftData 持久化、手表 App、小组件、通知、AI、设计系统。看到 PRD 里有这些也不要实现。

## 1. 环境事实（已核实）

- Xcode 27.1 位于 `/Applications/Xcode.app`，但 `xcode-select` 指向的是 CommandLineTools。**每一条** `xcodebuild` / `xcrun` / `swift test` 命令前都要加：
  ```bash
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  ```
  不要执行 `sudo xcode-select`。
- iOS SDK 27.1，watchOS SDK 27.0；Swift 6.4；XcodeGen 2.43.0 已安装（`/opt/homebrew/bin/xcodegen`）。
- 如果出现 “You have not agreed to the Xcode license agreements” 的报错：**立即停止**，在报告里请用户执行 `sudo xcodebuild -license accept`，不要尝试绕过。
- 部署目标：iOS 26.0。
- 钥匙串中已有的签名身份（`security find-identity -v -p codesigning`）：`Apple Development: 8615869003836 (7R599WMS2S)`、`Apple Distribution: guotong Liao (29UZBBVLS8)`。**哪一个是企业分发证书，以描述文件为准**（见 §9 阶段 F），不要自行假设。
- 本机目前没有安装任何描述文件（.mobileprovision）。
- 不确定某个 HealthKit API 的签名时，**不要猜**，去 SDK 中查：
  ```bash
  SDK=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk
  grep -n "关键字" $SDK/System/Library/Frameworks/HealthKit.framework/Modules/HealthKit.swiftmodule/arm64e-apple-ios.swiftinterface
  ls $SDK/System/Library/Frameworks/HealthKit.framework/Headers
  ```
- 已核实的 API：
  - `HKHeartbeatSeriesQueryDescriptor(_ sample: HKHeartbeatSeriesSample)`，调用 `.results(for: healthStore)` 返回 AsyncSequence；元素 `Heartbeat` 有两个字段：`timeIntervalSinceStart: TimeInterval` 和 `precededByGap: Bool`。
  - 心跳序列类型：`HKSeriesType.heartbeat()`。
  - 存在的数量类型标识：`.heartRateVariabilitySDNN`、`.restingHeartRate`、`.respiratoryRate`、`.oxygenSaturation`、`.appleSleepingWristTemperature`、`.appleSleepingBreathingDisturbances`、`.heartRateRecoveryOneMinute`、`.heartRate`。
  - 睡眠类型：`HKCategoryType(.sleepAnalysis)`，取值见 `HKCategoryValueSleepAnalysis`（`inBed`、`awake`、`asleepCore`、`asleepDeep`、`asleepREM`、`asleepUnspecified`）。

## 2. 硬性规则

1. 只用 Apple 一方框架，**不引入任何第三方依赖**。
2. Swift 6 语言模式，开启完整并发检查；不使用 `@unchecked Sendable` 或 `nonisolated(unsafe)` 来消除警告，除非在报告中说明原因。
3. `VigorScoring` **不得** `import HealthKit`、`SwiftUI`、`UIKit`，只能依赖 Foundation，全部是纯函数或值类型。
4. 所有界面文案使用简体中文；代码标识符使用英文。
5. 不要修改 `docs/PRD.md`。
6. 每完成一个阶段（§9）就运行该阶段的验证命令，确认通过后再进入下一阶段。
7. 某个错误连续修 3 次都没修好时，停下来，把错误原文写进报告，不要大面积重写来绕过。

## 3. 目录结构（最终状态）

```
whoop/
├── project.yml
├── .gitignore
├── Config/
│   ├── Signing.xcconfig            （阶段 A 先建空文件，阶段 F 填入签名信息）
│   └── ExportOptions.plist         （阶段 F 生成）
├── signing/                        （用户放置企业描述文件；不入库）
├── dist/                           （导出的 IPA；不入库）
├── App/
│   ├── Info.plist                  （由 XcodeGen 生成，不手写）
│   ├── Vigor.entitlements          （由 XcodeGen 生成，不手写）
│   ├── VigorApp.swift
│   ├── Lab/
│   │   ├── LabModel.swift          （@MainActor @Observable）
│   │   ├── LabRootView.swift
│   │   ├── OverviewSection.swift
│   │   ├── NightRow.swift
│   │   ├── NightDetailView.swift
│   │   ├── SegmentDetailView.swift
│   │   └── HypnogramChart.swift
│   └── Support/
│       └── Formatters.swift
├── Packages/
│   ├── VigorScoring/
│   │   ├── Package.swift
│   │   ├── Sources/VigorScoring/
│   │   │   ├── Models.swift
│   │   │   ├── HRVConfig.swift
│   │   │   ├── SleepSessionBuilder.swift
│   │   │   ├── RRProcessor.swift
│   │   │   ├── NightHRVAggregator.swift
│   │   │   ├── NightRestingHR.swift
│   │   │   └── NightAnalyzer.swift
│   │   └── Tests/VigorScoringTests/  （每个算法文件对应一个测试文件）
│   └── VigorHealth/
│       ├── Package.swift
│       ├── Sources/VigorHealth/
│       │   ├── HealthDataSource.swift   （协议）
│       │   ├── LiveHealthDataSource.swift   （#if os(iOS) || os(watchOS)）
│       │   ├── ReplayHealthDataSource.swift
│       │   ├── SyntheticSnapshot.swift
│       │   └── SnapshotCoding.swift
│       └── Tests/VigorHealthTests/
└── docs/
    ├── PRD.md
    └── M0-REPORT.md                 （最后写）
```

## 4. 工程配置

### 4.1 `project.yml`（照此编写，只在编译需要时微调）

```yaml
name: Vigor
options:
  bundleIdPrefix: com.example.vigor
  deploymentTarget:
    iOS: "26.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    DEVELOPMENT_TEAM: ""          # 用户之后填入企业团队 ID
packages:
  VigorScoring:
    path: Packages/VigorScoring
  VigorHealth:
    path: Packages/VigorHealth
targets:
  Vigor:
    type: application
    platform: iOS
    sources: [App]
    dependencies:
      - package: VigorScoring
      - package: VigorHealth
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: 元气
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        NSHealthShareUsageDescription: 元气需要读取睡眠、心率、心率变异性等健康数据，用于在本机计算恢复与睡眠分析。数据不会离开你的设备。
        NSHealthUpdateUsageDescription: 元气会在你进行晨测时写入正念记录。
    entitlements:
      path: App/Vigor.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []
        com.apple.developer.healthkit.background-delivery: true
    configFiles:
      Release: Config/Signing.xcconfig
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.vigor
        TARGETED_DEVICE_FAMILY: "1"
        CODE_SIGN_STYLE: Automatic
```

说明：
- M0 **不加** App Groups，等到 M4 做小组件时再加。这样描述文件只需要包含 HealthKit 能力。
- `Config/Signing.xcconfig` 在阶段 F 中生成，用于覆盖 Release 配置下的 Bundle ID、团队和签名设置。阶段 A–E 期间先创建一个**空文件**占位，保证 XcodeGen 能正常生成工程。

### 4.2 两个 Package 的 `Package.swift`

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VigorScoring",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [.library(name: "VigorScoring", targets: ["VigorScoring"])],
    targets: [
        .target(name: "VigorScoring"),
        .testTarget(name: "VigorScoringTests", dependencies: ["VigorScoring"]),
    ]
)
```

`VigorHealth` 的写法相同，只是依赖 `.package(path: "../VigorScoring")`，target 依赖 `"VigorScoring"`。测试一律使用 **Swift Testing**（`import Testing`、`@Test`、`#expect`），不使用 XCTest。

### 4.3 `.gitignore`
需要忽略：`*.xcodeproj`（由 XcodeGen 生成）、`.build/`、`build/`、`dist/`、`signing/`（描述文件不入库）、`DerivedData/`、`xcuserdata/`、`.DS_Store`、`.swiftpm/`。

## 5. VigorScoring：领域模型与算法

### 5.1 `Models.swift`（全部类型遵循 `Codable, Sendable, Hashable`）

```swift
public enum SleepStage: String { case inBed, awake, core, deep, rem, asleepUnspecified
    public var isAsleep: Bool { self == .core || self == .deep || self == .rem || self == .asleepUnspecified } }

public struct SleepStageSample { public var start: Date; public var end: Date; public var stage: SleepStage; public var sourceIsWatch: Bool }
public struct HeartRateSample  { public var date: Date; public var bpm: Double }
public struct ValueSample      { public var start: Date; public var end: Date; public var value: Double }
public struct Beat             { public var t: TimeInterval; public var precededByGap: Bool }   // t = 距序列开始的秒数
public struct HeartbeatSeries  { public var id: UUID; public var start: Date; public var end: Date; public var beats: [Beat] }

public enum BiologicalSex: String { case male, female, other, unknown }
public struct UserProfile { public var birthYear: Int?; public var sex: BiologicalSex }

public struct HealthSnapshot {
    public var schemaVersion: Int            // 固定为 1
    public var exportedAt: Date
    public var rangeStart: Date
    public var rangeEnd: Date
    public var profile: UserProfile
    public var sleep: [SleepStageSample]
    public var heartRate: [HeartRateSample]
    public var hrvSDNN: [ValueSample]            // 单位 ms
    public var restingHeartRate: [ValueSample]   // 单位 bpm
    public var respiratoryRate: [ValueSample]    // 单位 次/分
    public var wristTemperature: [ValueSample]   // 单位 °C
    public var oxygenSaturation: [ValueSample]   // 0–1 的小数
    public var heartbeatSeries: [HeartbeatSeries]
}
```
所有类型都要提供 `public init`。

### 5.2 `HRVConfig.swift`

```swift
public struct HRVConfig: Sendable, Hashable, Codable {
    public var minRRms = 300.0
    public var maxRRms = 2000.0
    public var maxSuccessiveChange = 0.20     // 相对上一个“被接受”的 RR
    public var minValidRR = 30
    public var maxRejectRate = 0.20
    public var lateSleepWeight = 1.5          // 片段中点落在睡眠后 1/3
    public var deepSleepWeight = 1.3          // 片段中点落在深睡分期内
    public var morningWindow: TimeInterval = 3600
    public var sessionMergeGap: TimeInterval = 3600
    public var napMaxDuration: TimeInterval = 3 * 3600
    public static let `default` = HRVConfig()
}
```

### 5.3 `SleepSessionBuilder.swift`

`public static func sessions(from samples: [SleepStageSample], calendar: Calendar, config: HRVConfig) -> [SleepSession]`

```swift
public struct SleepSession: Sendable, Hashable, Codable {
    public var start: Date            // 第一个“睡着”样本的开始时间
    public var end: Date              // 最后一个“睡着”样本的结束时间
    public var stages: [SleepStageSample]   // 落在 [start, end] 内的睡着与清醒样本
    public var asleepDuration: TimeInterval // 各睡着分期的时长之和
    public var wakeDay: DateComponents      // end 所在的本地日期（年、月、日）
    public var isMain: Bool
}
```
规则：
1. 只使用 `sourceIsWatch == true` 的样本；丢弃 `inBed`。
2. 样本按开始时间排序后依次合并：如果当前样本的开始时间减去当前会话的结束时间 ≤ `sessionMergeGap`，就并入当前会话，否则开启新会话。
3. 会话的首尾只由睡着类分期决定（清醒样本可以在中间，但不能作为首尾）；没有任何睡着分期的会话直接丢弃。
4. 同一个 `wakeDay` 中 `asleepDuration` 最长的会话设为 `isMain = true`；其余会话中，`asleepDuration < napMaxDuration` 的当作小睡（`isMain = false`），否则也标记为 `isMain = false`（M0 不做进一步处理）。
5. 重叠样本（Apple 有时会给出重叠分期）：计算 `asleepDuration` 时按时间做并集去重，不能重复累加。

### 5.4 `RRProcessor.swift`

`public static func analyze(_ series: HeartbeatSeries, config: HRVConfig) -> SegmentResult`

```swift
public struct SegmentResult: Sendable, Hashable, Codable {
    public var seriesID: UUID
    public var start: Date; public var end: Date
    public var candidateRR: Int        // 可计算出的 RR 总数
    public var acceptedRR: Int
    public var rejectedRR: Int
    public var rmssd: Double?          // ms
    public var isValid: Bool
    public var invalidReason: String?  // “有效 RR 不足”、“伪迹比例过高”
    public var acceptedRRms: [Double]  // 供图表使用
    public var acceptedRRTimes: [TimeInterval] // 每个被接受 RR 对应的 beat 时间（秒）
}
```
算法（必须严格按以下步骤）：
1. 对第 i 个 beat（i ≥ 1）：如果 `beats[i].precededByGap == true`，这个 beat 不产生 RR，并且**打断连续性**；否则 `rr = (beats[i].t − beats[i−1].t) × 1000`，计入 `candidateRR`。
2. 某个 RR 落在 [minRRms, maxRRms] 之外 → 拒绝，并打断连续性。
3. 如果存在“上一个被接受的 RR”，而且两者之间没有发生打断，则当 `|rr − prev| / prev > maxSuccessiveChange` 时 → 拒绝，并打断连续性。
4. 否则接受该 RR。
5. **只有**两个相邻被接受的 RR 之间没有发生任何打断时，才计算差值 Δ = rr − prev。
6. RMSSD = √(Σ Δ² / Δ 的个数)；Δ 的个数为 0 时，RMSSD 为 nil。
7. `isValid = acceptedRR ≥ minValidRR && rejectedRR / candidateRR ≤ maxRejectRate && rmssd != nil`。

### 5.5 `NightHRVAggregator.swift`

`public static func aggregate(session: SleepSession, segments: [SegmentResult], sdnn: [ValueSample], config: HRVConfig) -> NightHRV`

```swift
public enum HRVMethod: String, Codable, Sendable { case morning, overnight, sdnnFallback, none }
public enum DataQuality: String, Codable, Sendable { case high, medium, low, none }
public struct NightHRV: Sendable, Hashable, Codable {
    public var rmssd: Double?
    public var method: HRVMethod
    public var overnightSegments: [SegmentResult]   // 中点落在 [session.start, session.end] 内
    public var morningSegments: [SegmentResult]     // 起点落在 (session.end, session.end + morningWindow] 内
    public var validOvernightCount: Int
    public var sdnnMean: Double?                    // 睡眠时段内 SDNN 样本的均值
    public var quality: DataQuality
}
```
规则：
1. 晨测片段中有有效的 → `method = .morning`，`rmssd` 取这些片段 RMSSD 的中位数，`quality = .high`。
2. 否则，夜间有效片段 ≥ 1 → `method = .overnight`：
   - 权重 = `acceptedRR` × (片段中点 ≥ start + 2/3 × 时长 ? lateSleepWeight : 1) × (片段中点落在任一 `deep` 分期内 ? deepSleepWeight : 1)
   - `rmssd = exp( Σ w·ln(rmssd) / Σ w )`
   - 质量：有效片段 ≥ 4 为 high；2–3 为 medium；1 为 low。
3. 否则，存在 SDNN → `method = .sdnnFallback`，`rmssd = nil`，`quality = .low`。
4. 都没有 → `method = .none`，`quality = .none`。

### 5.6 `NightRestingHR.swift`

`public static func compute(heartRate: [HeartRateSample], session: SleepSession) -> Double?`
- 取 `session` 时段内的心率样本，少于 10 个 → 返回 nil。
- 对每个样本 i，计算 [tᵢ, tᵢ + 300 s] 区间内所有样本的均值，返回所有均值中的最小值。

### 5.7 `NightAnalyzer.swift`

```swift
public struct NightReport: Sendable, Hashable, Codable, Identifiable {
    public var id: Date { session.end }
    public var session: SleepSession
    public var hrv: NightHRV
    public var nightRHR: Double?
    public var appleRHR: Double?           // wakeDay 当天的 restingHeartRate 值
    public var respiratoryRate: Double?    // 时段内均值
    public var wristTemperature: Double?   // 结束时间落在 wakeDay 内的样本
    public var spo2Mean: Double?           // 时段内均值
    public var heartRateCount: Int         // 时段内心率样本数
}
public enum NightAnalyzer {
    public static func analyze(_ snapshot: HealthSnapshot, calendar: Calendar, config: HRVConfig = .default) -> [NightReport]
}
```
只为 `isMain == true` 的会话生成报告，按时间倒序返回。

再提供一个汇总结构，用于实验室页的“可用性总览”：
```swift
public struct AvailabilitySummary: Sendable, Hashable {
    public var nights: Int
    public var nightsWithRMSSD: Int
    public var meanValidSegmentsPerNight: Double
    public var medianRMSSD: Double?
    public var qualityCounts: [DataQuality: Int]
    public static func make(_ reports: [NightReport]) -> AvailabilitySummary
}
```

### 5.8 必须写的测试（期望值必须精确）

| 测试 | 输入 | 期望 |
|---|---|---|
| RMSSD 基础 | beats 的 t 为 0, 1.000, 2.010, 3.000, 4.000（无间隙） | RR = [1000, 1010, 990, 1000]，Δ = [10, −20, 10]，RMSSD = √200 ≈ 14.1421（容差 1e-6） |
| 越界拒绝 | 序列中有一个 2500 ms 的 RR | 该 RR 被拒绝；跨过它的 Δ 不计算 |
| 突变拒绝 | 1000, 1000, 1300, 1000 | 1300 被拒绝（变化 30%）；它之后的 1000 与前一个被接受的 1000 之间发生了打断，不计算 Δ |
| 间隙打断 | 某个 beat 的 `precededByGap = true` | 该位置不产生 RR，也不跨它计算 Δ |
| 有效性 | 只有 20 个 RR | `isValid == false`，原因为“有效 RR 不足” |
| 聚合均值 | 两个有效夜间片段，RMSSD 分别为 20 和 40，权重相同 | rmssd = √800 ≈ 28.2843 |
| 晨测优先 | 同时有夜间片段和有效晨测片段 | `method == .morning` |
| SDNN 兜底 | 没有片段，只有 SDNN | `method == .sdnnFallback`，`rmssd == nil` |
| 会话合并 | 两段睡眠间隔 50 分钟 | 合并成一个会话 |
| 会话拆分 | 两段间隔 2 小时 | 拆成两个会话；更长的那个为主睡眠 |
| 重叠去重 | 两个完全重叠的 1 小时 core 样本 | `asleepDuration == 3600` |
| 跨零点 | 23:30 入睡、07:00 醒来 | `wakeDay` 为次日 |
| 夜间静息心率 | 9 个样本 | nil |
| 夜间静息心率 | 构造一个 5 分钟窗口均值最低为 48 的序列 | 48 |

测试中统一使用 `TimeZone(identifier: "Asia/Shanghai")` 的 Calendar，避免受本机时区影响。

## 6. VigorHealth：数据源

### 6.1 协议

```swift
public protocol HealthDataSource: Sendable {
    var kind: DataSourceKind { get }
    func requestAuthorization() async throws
    func snapshot(from: Date, to: Date, progress: @Sendable (Double, String) -> Void) async throws -> HealthSnapshot
}
public enum DataSourceKind: String, Sendable { case live, synthetic, imported }
```

### 6.2 `LiveHealthDataSource`（整个文件包在 `#if os(iOS) || os(watchOS)` 中）
- 持有一个 `HKHealthStore`。
- 读取权限：§1 列出的全部数量类型 + 睡眠 + `HKSeriesType.heartbeat()` + `HKObjectType.workoutType()` + 生日、性别等特征 + `mindfulSession`。写入权限：`mindfulSession`。
- 查询使用 `HKSampleQueryDescriptor` 的 async API，按开始时间升序。
- 单位：心率 `count/min`；SDNN 使用 `.secondUnit(with: .milli)`；温度 `.degreeCelsius()`；血氧 `.percent()`（得到 0–1 的小数）；呼吸率 `count/min`。
- `sourceIsWatch`：`sample.sourceRevision.productType?.hasPrefix("Watch") == true`。
- 心跳序列：先查询出 `HKHeartbeatSeriesSample` 列表，再**逐个顺序**执行 `HKHeartbeatSeriesQueryDescriptor(sample).results(for: store)`，把结果收集成 `[Beat]`；每完成一个就回调一次 progress。
- 生日和性别：`try? store.dateOfBirthComponents()`、`try? store.biologicalSex()`，失败就留空。

### 6.3 `SyntheticSnapshot.make(nights: Int = 30, seed: UInt64 = 42, endingAt: Date, calendar: Calendar) -> HealthSnapshot`
- 使用自己实现的 SplitMix64 种子随机数生成器，保证结果**完全可复现**。
- 每晚约 23:00–00:30 入睡，睡 6.5–8.5 小时；分期按约 90 分钟的周期循环（core → deep → core → rem），前半夜深睡多、后半夜 REM 多，中间穿插 2–4 段 3–8 分钟的清醒。
- 睡眠期间心率每 5 分钟一个点，数值约 48–62，后半夜逐渐下降。
- 每晚 4–10 段心跳序列，每段约 60 秒；RR 基线约 1050–1200 ms，加入呼吸性窦性心律不齐（正弦波，幅度 20–60 ms）和随机噪声；约 3% 的 beat 注入伪迹（RR 偏离 ±40%），约 1% 设置 `precededByGap`。
- 夜晚序号 `i % 10 == 3` 的夜晚**没有任何**心跳序列，也没有晨测（用来覆盖 SDNN 兜底；30 晚中正好有 3 晚）；`i % 5 == 1` 的夜晚在醒来后 20 分钟有一段晨测序列。用序号而不是随机数决定，保证测试结果确定。
- 同时生成 SDNN、Apple RHR、呼吸率、温度、血氧的样本。
- `sourceIsWatch = true`。

### 6.4 `ReplayHealthDataSource`
- 可以用 `HealthSnapshot` 初始化（kind 为 `.synthetic` 或 `.imported`）。
- `snapshot(from:to:)` 返回按时间裁剪后的子集。
- `requestAuthorization()` 什么都不做。

### 6.5 `SnapshotCoding`
- `encode(_:) -> Data` 和 `decode(_:) -> HealthSnapshot`；`JSONEncoder` 使用 `.secondsSince1970` 日期编码、`.sortedKeys` 输出格式。
- 遇到 `schemaVersion != 1` 时抛出明确的错误。

### 6.6 VigorHealth 的测试
- 编码 → 解码往返后结果相等。
- 相同种子生成两次快照，结果相等；不同种子则不相等。
- 用合成快照跑 `NightAnalyzer`：报告数量 == 30；`nightsWithRMSSD` == 27；`method == .sdnnFallback` 的夜晚 == 3；所有 RMSSD 都落在 15–120 ms。数字对不上时，要去排查算法或生成器，**不允许放宽断言**。

## 7. App：实验室页面

### 7.1 `VigorApp`
- 根视图为 `LabRootView`，外层包一个 `NavigationStack`。
- 默认数据源：模拟器（`#if targetEnvironment(simulator)`）使用 synthetic，真机使用 live。

### 7.2 `LabModel`（`@MainActor @Observable`）
- 状态：`source: DataSourceKind`、`isLoading`、`progress: Double`、`progressText`、`reports: [NightReport]`、`summary: AvailabilitySummary?`、`snapshot: HealthSnapshot?`、`errorMessage: String?`。
- `load(nights: 30)`：在后台取快照（不能阻塞主线程）→ 调用 `NightAnalyzer` → 更新状态。
- `switchSource(_:)`、`importSnapshot(from url: URL)`、`exportSnapshotFile() -> URL`（把 JSON 写到临时目录，文件名为 `vigor-snapshot-yyyyMMdd-HHmm.json`）。

### 7.3 界面（使用系统 `List` 的 `.insetGrouped` 样式，模仿 Apple Health 的克制风格）

**LabRootView**（大标题“实验室”）
1. 区块“数据源”：分段选择“实时 / 合成 / 导入”；实时模式下显示“授权健康数据”按钮；“导入快照”使用 `.fileImporter` 选 JSON 文件；“导出快照”按钮先调用 `exportSnapshotFile()` 生成文件，把 URL 存进状态，再显示 `ShareLink(item: url)`（或用 sheet 呈现分享）。
2. 区块“可用性总览”（`OverviewSection`）：夜数、可计算 RMSSD 的夜数（以及百分比）、平均每晚有效片段数、RMSSD 中位数、质量分布（高/中/低/无）。**这是 M0 判断方案可不可行的核心指标，字号要大、信息要清楚。**
3. 区块“最近 30 晚”：每行是一个 `NightRow`，点击进入详情。
4. 加载中显示 `ProgressView(value:)` 和进度文字；出错时显示错误信息并提供“重试”按钮。

**NightRow**：醒来日期（例如“10月20日 周一”）、睡眠时长（“7小时12分”）、RMSSD（“42 ms”或“—”）、有效片段数/总片段数（“5/7 段”）、夜间静息心率，以及左侧的质量色点（高=绿、中=黄、低=橙、无=灰）。

**NightDetailView**
- 摘要卡：入睡与醒来时间、睡眠时长、RMSSD 及计算方法（晨测/夜间/SDNN 兜底/无）、质量、夜间静息心率与 Apple 静息心率对比、呼吸率、手腕温度、血氧、心率样本数。
- `HypnogramChart`：用 Swift Charts 的 `RectangleMark` 画睡眠分期，纵轴依次为清醒、REM、核心、深睡；在上面叠加片段位置的竖线（有效为蓝色，无效为灰色）。
- 片段列表：时间、候选/接受/拒绝的 RR 数、RMSSD、有效或无效原因；分成“夜间”和“晨测”两组。点击进入 `SegmentDetailView`。

**SegmentDetailView**
- RR 心动周期图：`LineMark`，横轴为时间（秒），纵轴为 RR（ms）。
- Poincaré 散点图：`PointMark`，横轴为 RRₙ，纵轴为 RRₙ₊₁，两轴等比例。
- 统计：RMSSD、平均 RR、换算出的平均心率。

### 7.4 格式化
`Formatters.swift` 集中放置所有日期、时长、数字格式化函数，使用 `zh_CN` 区域。

## 8. Git
1. 在项目根目录执行 `git init`（如果还不是 git 仓库）。
2. 每完成 §9 的一个阶段就提交一次，提交信息使用英文 Conventional Commits 格式，例如 `feat(scoring): add RR processing and RMSSD`。
3. 不要 push，也不要添加远程仓库。

## 9. 执行阶段与验证

每个阶段都必须运行下列命令，并确认通过：

**阶段 A：骨架**
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd /Users/zxz/Vibecoding/whoop && xcodegen generate
xcodebuild -project Vigor.xcodeproj -scheme Vigor -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build -quiet
```

**阶段 B：VigorScoring**
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd /Users/zxz/Vibecoding/whoop/Packages/VigorScoring && swift test
```
§5.8 中的全部测试都必须通过。

**阶段 C：VigorHealth**
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd /Users/zxz/Vibecoding/whoop/Packages/VigorHealth && swift test
```

**阶段 D：App**
1. 重新执行阶段 A 的构建命令，要求 0 个 error，并且自己写的代码中 0 个 warning。
2. 在模拟器中运行并截图：
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl list devices available | grep iPhone        # 挑一台 iPhone，记下它的 UDID
xcrun simctl boot <UDID> || true
xcodebuild -project Vigor.xcodeproj -scheme Vigor -destination "id=<UDID>" -derivedDataPath build CODE_SIGNING_ALLOWED=NO build -quiet
xcrun simctl install <UDID> build/Build/Products/Debug-iphonesimulator/Vigor.app
xcrun simctl launch <UDID> com.example.vigor
sleep 5 && xcrun simctl io <UDID> screenshot docs/m0-lab.png
```
截图中应能看到“可用性总览”，并且数字非空。如果启动后闪退，用 `xcrun simctl spawn <UDID> log show --last 2m --predicate 'process == "Vigor"'` 查看原因。

**阶段 E：提交代码**
确认阶段 A–D 全部通过后，提交一次。

**阶段 F：企业签名 IPA**

输入：用户把企业（In-House）描述文件放在 `signing/` 目录下（任意文件名，扩展名为 `.mobileprovision`）。**如果目录不存在或里面没有描述文件，跳过本阶段，在报告中写明“缺少描述文件”，然后直接进入阶段 G。**

1. 解析描述文件：
   ```bash
   security cms -D -i signing/<文件>.mobileprovision > build/profile.plist
   /usr/libexec/PlistBuddy -c 'Print :Name' build/profile.plist
   /usr/libexec/PlistBuddy -c 'Print :UUID' build/profile.plist
   /usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' build/profile.plist
   /usr/libexec/PlistBuddy -c 'Print :ExpirationDate' build/profile.plist
   /usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' build/profile.plist
   /usr/libexec/PlistBuddy -c 'Print :Entitlements' build/profile.plist
   ```
2. 校验以下各项，**任何一项不通过就停止本阶段**，把原因写进报告：
   - `ProvisionsAllDevices == true`（企业描述文件的标志；ad-hoc 或开发描述文件没有这个字段）。
   - 没有过期。
   - `Entitlements` 中的 `application-identifier` 是 `<TeamID>.<明确的 Bundle ID>`，**不能是通配符 `*`**（HealthKit 不支持通配符 App ID）。
   - `Entitlements` 中包含 `com.apple.developer.healthkit = true`。
   - 描述文件中 `DeveloperCertificates` 里的证书，必须和钥匙串中某个签名身份的 SHA-1 一致。比对方法：把 `DeveloperCertificates:0` 导出为 DER 文件，用 `openssl x509 -inform DER -noout -fingerprint -sha1` 计算指纹，再和 `security find-identity -v -p codesigning` 中显示的 SHA-1 对比（去掉冒号、统一大小写后比较）。记下匹配到的身份全名。
3. 安装描述文件（两个位置都放，兼容新旧版本的 Xcode）：
   ```bash
   mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles
   cp signing/<文件>.mobileprovision ~/Library/MobileDevice/Provisioning\ Profiles/<UUID>.mobileprovision
   cp signing/<文件>.mobileprovision ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/<UUID>.mobileprovision
   ```
4. 用解析出的值生成 `Config/Signing.xcconfig`：
   ```
   PRODUCT_BUNDLE_IDENTIFIER = <从 application-identifier 中去掉 TeamID 前缀后的部分>
   DEVELOPMENT_TEAM = <TeamID>
   CODE_SIGN_STYLE = Manual
   CODE_SIGN_IDENTITY = <第 2 步中匹配到的身份全名>
   PROVISIONING_PROFILE_SPECIFIER = <Name>
   ```
   然后执行 `xcodegen generate`。
5. 生成 `Config/ExportOptions.plist`：`method = enterprise`、`teamID`、`signingStyle = manual`、`signingCertificate = <身份全名>`、`provisioningProfiles = { <Bundle ID>: <Name> }`、`stripSwiftSymbols = true`、`thinning = <none>`。
6. 归档并导出：
   ```bash
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   cd /Users/zxz/Vibecoding/whoop
   xcodebuild -project Vigor.xcodeproj -scheme Vigor -configuration Release \
     -destination 'generic/platform=iOS' -archivePath build/Vigor.xcarchive archive
   xcodebuild -exportArchive -archivePath build/Vigor.xcarchive \
     -exportPath build/export -exportOptionsPlist Config/ExportOptions.plist
   mkdir -p dist && cp build/export/*.ipa dist/Vigor-0.1.0-1.ipa
   ```
7. 验证 IPA：
   ```bash
   rm -rf build/ipa-check && mkdir -p build/ipa-check && cd build/ipa-check && unzip -q ../../dist/Vigor-0.1.0-1.ipa
   codesign --verify --deep --strict --verbose=2 Payload/Vigor.app
   codesign -d --entitlements - Payload/Vigor.app
   ```
   要求：签名校验通过；entitlements 中包含 `com.apple.developer.healthkit`；`get-task-allow` 为 false 或不存在；`application-identifier` 和描述文件一致。
8. 签名相关的报错（例如 “No profile for team”、“doesn't include signing certificate”）**不要反复尝试**：把完整报错和第 1 步解析出的字段一起写进报告，然后停止。绝不能改用开发证书或 ad-hoc 来“凑”出一个 IPA。

**阶段 G：报告**
新建 `docs/M0-REPORT.md`，包含以下内容：
- 完成清单（对照本文 §5–§7 和阶段 F 逐项标注 ✅ 或 ❌）
- 各阶段验证命令的输出摘要（测试通过数、构建结果、IPA 路径和大小、描述文件的名称和到期日）
- 偏离本文档的决策及原因
- 还没有验证的部分（**真机上的 HealthKit 读取无法在模拟器中验证，必须明确写出来**）
- 给用户的安装与验证步骤：
  1. 用 Mac 的“访达”（iPhone 连接后在侧边栏选中它）或 Apple Configurator，把 `dist/Vigor-0.1.0-1.ipa` 拖进去安装
  2. 在 iPhone 的“设置 → 通用 → VPN 与设备管理”中信任企业开发者
  3. 打开 App → 实验室 → 切到“实时” → 授权健康数据
  4. 截图“可用性总览”，导出快照 JSON 发回

## 10. 完成标准（全部满足才算完成）
- [ ] `swift test` 在两个 Package 中全部通过
- [ ] iOS 模拟器构建 0 个 error
- [ ] 模拟器截图中的“可用性总览”显示合成数据，且数字合理
- [ ] 实时数据源的代码可以编译（真机验证留给用户）
- [ ] `dist/Vigor-0.1.0-1.ipa` 已生成，并通过阶段 F 第 7 步的校验（如果缺少描述文件，就在报告中写明原因）
- [ ] `docs/M0-REPORT.md` 已写好
- [ ] 所有改动都已在本地 git 中提交
