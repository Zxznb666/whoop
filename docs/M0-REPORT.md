# 元气 Vigor · M0 报告

**状态**：M0 全部阶段已完成（A–D 验证通过，E 本报告）。真机 HealthKit 读取尚未验证，见 §5。
**日期**：2026-10-21
**环境**：Xcode 27.1（iOS SDK 27.1，Swift 6.4），XcodeGen 2.43.0，模拟器 iPhone 17 Pro（iOS 26.5）

## 1. 完成清单

对照施工文档 §5–§7。✅ 已实现并通过验证，⚠️ 已实现但只做了编译验证，❌ 未完成。

### §5 VigorScoring（纯算法）

| 条目 | 状态 | 说明 |
|---|---|---|
| §5.1 `Models.swift` | ✅ | 全部类型 `Codable, Sendable, Hashable`，均有 `public init` |
| §5.2 `HRVConfig.swift` | ✅ | 参数与文档一致 |
| §5.3 `SleepSessionBuilder.swift` | ✅ | 规则 1–5 全部实现；合并间隔的解释见 §3 偏离第 3 条 |
| §5.4 `RRProcessor.swift` | ✅ | 步骤 1–7 严格按文档实现 |
| §5.5 `NightHRVAggregator.swift` | ✅ | 晨测优先、几何加权、SDNN 兜底、none |
| §5.6 `NightRestingHR.swift` | ✅ | 5 分钟窗口均值的最小值，不足 10 个样本返回 nil |
| §5.7 `NightAnalyzer.swift` | ✅ | 只为主睡眠生成报告，按时间倒序；`AvailabilitySummary.make` 已实现 |
| §5.8 测试 | ✅ | 文档表中 14 行全部有对应测试，期望值精确（见 §2） |

### §6 VigorHealth（数据源）

| 条目 | 状态 | 说明 |
|---|---|---|
| §6.1 `HealthDataSource` 协议 | ✅ | |
| §6.2 `LiveHealthDataSource` | ⚠️ | 仅 iOS/watchOS 编译，已通过 iOS 模拟器构建；真机读取未验证 |
| §6.3 `SyntheticSnapshot` | ✅ | SplitMix64；30 晚；`i%10==3` 无序列、`i%5==1` 有晨测；全部值域与文档一致 |
| §6.4 `ReplayHealthDataSource` | ✅ | 按时间裁剪；`requestAuthorization` 为空操作 |
| §6.5 `SnapshotCoding` | ✅ | `.secondsSince1970` + `.sortedKeys`；版本不为 1 时抛出 `unsupportedSchemaVersion` |
| §6.6 测试 | ✅ | 往返相等、同种子相等、不同种子不等；30 晚、27 有 RMSSD、3 晚兜底、RMSSD 落在 15–120 ms |

### §7 App（实验室页）

| 条目 | 状态 | 说明 |
|---|---|---|
| §7.1 `VigorApp` | ✅ | 外层 `NavigationStack`；模拟器默认合成，真机默认实时 |
| §7.2 `LabModel` | ✅ | `@MainActor @Observable`；后台任务取快照与分析；导入、导出、授权均已实现 |
| §7.3 `LabRootView` | ✅ | 数据源分段选择、授权、导入（`.fileImporter`）、导出（`ShareLink`）、加载进度、错误与重试 |
| §7.3 `OverviewSection` | ✅ | 已在模拟器中看到数字（见 §2 阶段 D） |
| §7.3 `NightRow` | ✅ | 已在模拟器列表中看到 |
| §7.3 `NightDetailView` | ⚠️ | 编译通过；模拟器中未打开查看 |
| §7.3 `HypnogramChart` | ⚠️ | 编译通过；模拟器中未打开查看 |
| §7.3 `SegmentDetailView` | ⚠️ | 编译通过；模拟器中未打开查看 |
| §7.4 `Formatters.swift` | ✅ | 统一 zh_CN |

### §8–§10 工程与完成标准

| 完成标准 | 状态 |
|---|---|
| `swift test` 在两个 Package 中全部通过 | ✅ VigorScoring 23 个，VigorHealth 8 个 |
| iOS 模拟器构建 0 个 error | ✅ |
| 模拟器截图中的“可用性总览”显示合成数据，数字合理 | ✅ 见 `docs/m0-lab.png` |
| 实时数据源的代码可以编译 | ✅ 已通过 iOS 模拟器构建 |
| `docs/M0-REPORT.md` 已写好 | ✅ 本文件 |
| 所有改动已在本地 git 中提交 | ✅ 见 §6（`docs/prompts/` 为用户原有文件，未纳入版本控制） |

## 2. 各阶段验证输出摘要

**阶段 A：骨架**
- `xcodegen generate`：成功生成 `Vigor.xcodeproj`。
- `xcodebuild -scheme Vigor -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`：`BUILD_EXIT=0`。
- 首次构建被 Xcode 许可协议阻塞（退出码 69），用户接受 Xcode 27.1 许可后通过。

**阶段 B：VigorScoring**
- `swift test`：`Test run with 23 tests in 5 suites passed`。
- 清理后重新构建 `swift build --build-tests`：无编译警告。

**阶段 C：VigorHealth**
- `swift test`：`Test run with 8 tests in 3 suites passed`。
- `xcodebuild -scheme VigorHealth -destination 'generic/platform=iOS Simulator' build`：`BUILD SUCCEEDED`，其中包含 `LiveHealthDataSource`。
- 清理后重新构建 `swift build --build-tests`：无编译警告。

**阶段 D：App**
- `xcodebuild -scheme Vigor -destination 'generic/platform=iOS Simulator' build`：`BUILD SUCCEEDED`，我们的代码 0 个 error、0 个 warning。构建日志中有一行 `appintentsmetadataprocessor ... Metadata extraction skipped`，属于构建工具的通知，与我们的代码无关。
- 模拟器：iPhone 17 Pro，应用启动正常，无闪退。
- 截图 `docs/m0-lab.png` 中的“可用性总览”（合成数据）：
  - 夜数 **30**
  - 可算 RMSSD **27**（占 90%）
  - 平均每晚有效片段 **6.3**
  - RMSSD 中位数 **41 ms**
  - 质量分布：高 **27**、中 **0**、低 **3**、无 **0**
  - “低”的 3 晚与合成数据中无心跳序列的 3 晚一致（SDNN 兜底）。

## 3. 偏离施工文档的决策及原因

1. **`VigorHealthTests` 直接依赖 `VigorScoring`**：`Package.swift` 的测试目标加上了 `"VigorScoring"`。测试文件直接 `import VigorScoring`，不依赖传递依赖。
2. **合成快照的时间戳对齐到整秒**：文档要求 §6.5 “编码 → 解码往返后结果相等”。实测 `Date` 经 `.secondsSince1970` 往返会丢失最后一位精度，导致相等判断失败。合成数据的所有 `Date`（睡眠分期、心率、序列起止等）都对齐到整秒，往返即可逐位相等。心跳的 `t` 是 `Double`，原样保存，不受影响。
3. **会话合并的间隔起点**：§5.3 第 2 条写的是“当前会话的结束时间”。我把它解释为当前组内所有样本（含清醒）的最大结束时间，这样清醒段之后的间隔按真实间隔计算。
4. **主睡眠判定**：按 §5.3 第 4 条，每个 `wakeDay` 中睡着时长最长的会话为主睡眠，不做 `napMaxDuration` 判定。`HRVConfig.napMaxDuration` 字段保留，M0 未使用。
5. **无效原因**：`RRProcessor` 中，RMSSD 为 nil 时归为“有效 RR 不足”，因为文档只定义了两种原因。`candidateRR == 0` 时视为无效。
6. **`SnapshotCoding.decode` 先读版本号**：先只解码 `schemaVersion`，版本不对就抛出明确错误，避免新版本结构导致含糊的解码错误。
7. **`LiveHealthDataSource` 用 `struct`**：`HKHealthStore` 在 SDK 中标注为 `NS_SWIFT_SENDABLE`，因此不需要 `@unchecked Sendable` 或 `nonisolated(unsafe)`。
8. **Poincaré 图的相邻判定**（仅视图层）：`SegmentResult` 不记录打断位置，视图用时间差判断相邻：两个被接受 RR 之间的拍间隔等于后一个 RR，才连线。模型本身未改动。
9. **`LabModel.exportSnapshotFile()` 声明为 `throws`**：文档签名没写 `throws`，但编码与写文件都可能失败。
10. **`LabModel` 的过期结果保护**：用 `generation` 计数，只有最新一次加载的结果会写入状态，避免切换数据源时旧结果覆盖新结果。
11. **`meanValidSegmentsPerNight`**：只计夜间有效片段，不含晨测，与 `NightHRV.validOvernightCount` 一致。
12. **合成数据的结束日期**：App 中以当前时间 `Date()` 作为 `endingAt`，所以截图里的日期会随运行日期变化。同一种子、同一 `endingAt` 的结果完全可复现。
13. **合成心率只覆盖睡眠期间**：文档 §6.3 只要求睡眠期间的心率。
14. **删除占位文件**：阶段 A 的 `Placeholder.swift` 和占位测试在阶段 B、C 中删除。

## 4. 施工文档与 PRD 的差异

以下差异按施工文档执行（施工文档优先）。M0 结束后需要决定是否回写 PRD，本次未修改 `docs/PRD.md`：

1. **睡眠会话合并**：PRD §5.2 用 45 分钟（分段睡眠到 120 分钟）；施工文档 §5.3 用 60 分钟。
2. **伪迹过滤**：PRD §5.3.2 用“与前后 5 拍中位数相差 >20%”加“早搏模式”；施工文档 §5.4 只用“相邻被接受 RR 变化 >20%”。
3. **夜间合并**：PRD §5.3.4 用 ln RMSSD 的加权中位数（≥3 段）；施工文档 §5.5 用几何加权平均。
4. **夜间静息心率**：PRD §5.4 用样本池的第 10 百分位；施工文档 §5.6 用 5 分钟窗口均值的最小值。

## 5. 未验证的部分

- **真机上的 HealthKit 读取无法在模拟器中验证，尚未验证。** 包括授权弹窗、各类数量与睡眠查询、心跳序列的读取耗时与进度回调，以及 `sourceIsWatch` 的判断（依赖 `sourceRevision.productType`）。
- `NightDetailView`、`SegmentDetailView`、`HypnogramChart` 只通过了编译，没有在模拟器中打开查看。
- “导入快照”和“导出快照”的界面流程没有在模拟器中实际点击验证（代码路径已实现，编解码由测试覆盖）。
- 合成数据的 RMSSD 分布只由测试中的范围断言（15–120 ms）覆盖，没有与真实数据对比。

## 6. Git

提交历史（本地，未推送）：

| 提交 | 内容 |
|---|---|
| `c84040c` | 工程骨架与包的占位 |
| `aecf3dc` | VigorScoring：睡眠会话、RR 处理、夜间 HRV、测试 |
| `89c4df5` | VigorHealth：数据源协议、回放、合成快照、编解码、实时数据源、测试 |
| `eddf039` | App：实验室界面与模拟器截图 |

提交作者是本机 git 配置的身份（`Zxznb666 <2993185616@qq.com>`）。如需改为其他身份，需要修改 git 配置后重写这些提交。

## 7. 给用户的真机验证步骤

1. 在 `project.yml` 中填入 `DEVELOPMENT_TEAM`，并把 `bundleIdPrefix` 与 `PRODUCT_BUNDLE_IDENTIFIER` 改为真实的 Bundle ID（当前为占位值 `com.example.vigor`）。
2. 重新生成工程：

```bash
cd /Users/zxz/Vibecoding/whoop && xcodegen generate
```

3. 用 Xcode 打开 `Vigor.xcodeproj`，选择真机作为运行目标并运行。
4. 在“实验室”页点击“授权健康数据”，并允许全部读取权限。
5. 把数据源切换到“实时”，等待加载完成。
6. 截图“可用性总览”。
7. 点击“导出快照”，把生成的 JSON 文件发回。
