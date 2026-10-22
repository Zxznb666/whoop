# 施工任务：元气 Vigor · M6 骑行界面补完

M6 骑行数据已完成到阶段 13（`dist/Vigor-1.2.0.ipa`）。`docs/DECISIONS.md` D-125 列出了几项**没有实现的界面**。本轮把它们**一次性补完**，最后打出 1.3.0 的包。

---

## 0. 开工前必读
1. `docs/prompts/M1-M5-build-prompt.md`：其中 §1（环境）、§2（硬性规则）、§6（进度文件）、§7（验证命令）**继续有效**。
2. `docs/prompts/M6-cycling-build-prompt.md`（骑行的原始规格），以及 `docs/DECISIONS.md` 中的 D-103 至 D-133，重点是 D-107、D-110、D-112、D-125、D-128 至 D-130。
3. 现有代码：`Packages/VigorScoring/Sources/VigorScoring/Cycling/`、`Load/HeartRateOrigin.swift`、`App/Cycling/CyclingViews.swift`、`App/Screens/CardioFitnessView.swift`、`Packages/VigorFIT/Sources/VigorFIT/RideStream.swift`（其中已有 `laps`）。
4. 进度记在 `docs/BUILD-PROGRESS.md` 末尾新增的“M6 补完 C1–C6”下；中断后从第一个未完成的项继续。
5. 不要提交 `docs/prompts/M6-cycling-build-prompt.md`（这是用户的文件，保持未提交状态）。

## 1. 本轮不许改动的部分
- 同步链路：`SyncEngine` 的刷新模式与快照缓存合并、`AppBootstrap.refreshNow` 的请求合并、`BackgroundSync` 的回调时机。**唯一允许的扩展**：C5 中给 `ScoringSettings` 增加一个字段，并传入流水线（与 F7 的方式相同）。
- 已有的骑行指标口径（NP、TSS、覆盖率门槛、D-128 的空档填充规则）不改。
- 已有测试不允许放宽断言。

## 2. 任务清单（按顺序执行，每项都要：实现 → 测试 → 构建 → 提交 → 更新进度）

### C1 骑行时间线数据（纯函数，放在 `VigorScoring/Cycling/RideTimeline.swift`）
为骑行详情的曲线准备数据，界面不直接处理原始样本。

```swift
public struct RideTimelinePoint: Sendable, Hashable, Codable {
    public var offset: TimeInterval      // 距骑行开始的秒数（桶的中点）
    public var heartRate: Double?        // 桶内平均；没有测量时为 nil
    public var power: Double?            // 桶内平均；没有测量时为 nil（不是 0）
    public var paused: Bool              // 桶内超过一半的秒处于暂停
}
public struct RideTimeline: Sendable, Hashable, Codable {
    public var points: [RideTimelinePoint]
    public var heartRateSource: HeartRateOrigin?
    public var powerSource: PowerSource
    public var laps: [RideLapSummary]
}
public struct RideLapSummary: Sendable, Hashable, Codable {
    public var index: Int
    public var start: Date
    public var durationSeconds: Int          // 有效骑行秒（不含暂停）
    public var distanceMeters: Double?
    public var averagePower: Double?
    public var normalizedPower: Double?      // 只在 ≥ 30 秒时计算
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
}
public enum RideTimelineBuilder {
    public static func build(ride: RideResult, snapshot: HealthSnapshot, importedRides: [RideStream], maxPoints: Int = 600) -> RideTimeline
}
```
规则：
- **数据来源**：有对应的 FIT（`RideResult` 的成员里有导入骑行）时，心率和功率都用 FIT 的逐秒数组。否则：心率用快照中落在骑行窗口内的心率样本，**按 D-130 的来源优先级逐分钟去重之后的结果**（复用现有的分类函数，不能另写一套优先级）；功率用快照中的 `cyclingPower` 样本，按样本的真实时间区间展开。HealthKit 样本之间超过 5 秒的空档记为 nil。
- **降采样**：把骑行时长平均分成 `min(maxPoints, 总秒数)` 个桶，桶内对非 nil 值取平均；桶内没有任何测量值时为 nil（这样图表的线会在缺失处断开，而不是连成一条直线）。
- **分圈**：只有 FIT 才有。按 `laps` 的起止切分逐秒数组计算各项；没有分圈时返回空数组。
- **测试**（期望值精确）：
  | 测试 | 期望 |
  |---|---|
  | FIT 恒定 3600 秒，心率 140、功率 200，maxPoints 600 | 600 个点，每点心率 140、功率 200 |
  | 骑行时长 300 秒，maxPoints 600 | 300 个点（每秒一个桶） |
  | HealthKit 功率样本中间有 60 秒空档 | 空档对应的点 `power == nil`，不是 0 |
  | 心率同时有 Garmin 与手表被动样本，且只有 Garmin 训练 | 使用 Garmin 的心率（D-130） |
  | FIT 两圈：第 1 圈 600 秒、功率 250，第 2 圈 600 秒、功率 150 | 两圈的平均功率分别为 250、150，NP 分别为 250、150 |
  | 第 3 圈只有 20 秒 | 这一圈的 `normalizedPower == nil` |

### C2 骑行详情：双轴曲线、分圈表、心率区间分布
在 `RideDetailView` 中新增三张卡片，数据来自 C1 和 C3：
1. **功率 / 心率双轴曲线**：Swift Charts 没有原生的双纵轴，按下面的方法实现：
   - 左轴为功率，范围 `0 … P_top`，`P_top` = max(功率最大值 × 1.1, FTP × 1.5)，取整到 50 W。
   - 心率先线性映射到功率刻度：`y = (hr − hr_low) / (hr_high − hr_low) × P_top`，其中 `hr_low` = 静息心率，`hr_high` = 最大心率（取流水线中这次骑行使用的值）。
   - 右轴用 `AxisMarks(position: .trailing, values:)` 在映射后的位置标注心率值（例如 100、120、140、160、180 bpm 中落在范围内的值）。
   - 功率用 `systemOrange`，心率用 `systemPink`（PRD §7.2），暂停的桶用浅灰色背景标出。
   - 支持拖动选中：显示该点的时间、功率、心率。
   - 映射函数写成纯函数并加测试：`hr_low` 100、`hr_high` 180、`P_top` 400 时，心率 140 → 200。
   - 只有心率或只有功率时，只画有的那一条，并隐藏另一侧的坐标轴。
2. **分圈表**：圈号、时长、距离、平均功率、NP、平均心率、最大心率；没有分圈（非 FIT 骑行）时不显示这张卡片。
3. **心率区间分布**：Z1–Z5，口径与 PRD §5.1 一致（按心率储备比 HRR%）。

### C3 每次骑行的心率区间（`VigorScoring`）
- 给 `RideResult` 增加 `heartRateZoneSeconds: [Int]?`（5 个元素，对应 Z1–Z5；HRR% < 50% 的秒不计入任何区间）。用流水线中这次骑行实际使用的心率序列计算（FIT 用逐秒心率，否则用去重后的分钟心率，每分钟计 60 秒）。
- `RideResult` 是 Codable，并且已经保存到存储中：新字段必须是可选的，旧数据解码不能失败。补一个旧 JSON 解码测试。
- 测试：静息心率 50、最大心率 190 时，心率 120 → HRR 0.5 → Z1；心率 169 → HRR 0.85 → Z4；心率 80 → 不计入。

### C4 浏览页：EF 趋势、FTP 历史；心肺适能新增两项
1. **FTP 历史**（`VigorScoring/Cycling/FTPHistory.swift`）：
   - 生成每周一个点（周一 00:00），覆盖最近 365 天：`[FTPPoint(date, watts, source)]`。
   - 每个点的取值优先级：当时生效的**手动设置** > 当时最新的 HealthKit `cyclingFunctionalThresholdPower` 样本 > 截至当时最近 90 天最佳 20 分钟功率 × 0.95 > 没有（nil）。
   - 手动设置的历史：从本版本开始，每次修改手动 FTP 时，把（日期, 值）追加保存到 UserDefaults；**在此之前的日期不使用手动值**（我们没有记录过它的历史）。清除手动值也要记录（值为 nil）。
   - 测试：只有一次骑行（最佳 20 分钟 280 W，在第 0 天）→ 第 0 天到第 90 天的点为 266 W，之后为 nil；手动设置从第 30 天开始为 250 → 第 30 天起为 250，来源为“手动”；HealthKit 样本在第 60 天为 270、没有手动值 → 第 60 天起为 270。
2. **EF 趋势**：每次有 EF 的骑行一个点，外加最近 90 天的线性斜率（每天）。测试：EF 从第 0 天的 1.40 线性增长到第 90 天的 1.49 → 斜率 0.001 / 天（±1e-9）。
3. **浏览页**的“骑行”类别新增两个入口：“FTP 历史”（折线图 + 来源说明）和“有氧效率 EF”（散点 + 趋势线 + 斜率文案，例如“近 90 天每月提高 0.03”）。复用现有的 `RangeChart` 或与它风格一致的图表。
4. **心肺适能页**（PRD §5.12.2）新增两项：EF 的 90 天趋势、90 天最佳 20 分钟功率的变化（本期 90 天对比上期 90 天，单位 W 和 %）。数据不足时显示“数据不足”。
5. 把 FTP 历史和 EF 趋势加进 `CyclingOutput`（Codable，新字段可选），随现有的 `saveCycling` 一起保存。

### C5 手动指定心率来源的偏好
1. 新增：
   ```swift
   public enum SourcePreference: String, Sendable, Hashable, Codable { case automatic, preferred, ignored }
   ```
   键为来源的 Bundle ID。
   - `automatic`：保持 D-130 的规则。
   - `preferred`：这个来源在**自己的训练时段内**的心率，优先级高于 Apple Watch 训练期间、低于 FIT 导入。
   - `ignored`：这个来源的心率样本不参与分钟去重，也不作为骑行的心率；它的训练记录仍然参与骑行分组。
2. `HeartRateOrigin` 新增一个 case，例如 `preferredWorkout`。**不要改动现有 case 的 rawValue**（它们已经保存在存储中）；把 `Comparable` 改为基于一个显式的 `rank` 属性来比较，使排序为 `fitImport > preferredWorkout > watchWorkout > otherWorkout > watchPassive > other`。补测试，确认旧数据的 rawValue 解码不变。
3. 偏好通过 `PipelineInput` 传入分类函数；`ScoringSettings` 增加 `heartRateSourcePreferences: [String: SourcePreference]`，在 `SyncEngine.refresh` 中传给 `PipelineInput`（这是 §1 唯一允许的同步链路改动）；`AppBootstrap.currentSettings()` 从 UserDefaults 读取。修改偏好后触发 `refreshNow(mode: .window(days: 30))`。
4. **设置**的骑行部分：列出最近 180 天内出现过的骑行训练来源和心率来源（显示名称 + Bundle ID + 样本数量），每个来源一个三选一的选择器；Apple Watch 不在列表中（它的规则固定）。
5. 测试：
   | 测试 | 期望 |
   |---|---|
   | Garmin 设为 `preferred`，同一分钟同时有手表训练心率和 Garmin 心率 | 取 Garmin |
   | Garmin 设为 `ignored` | 这一分钟取手表的心率；骑行分组的数量不变 |
   | 没有任何偏好 | 结果与修改前完全相同（黄金快照不变） |
   | 偏好通过 `SyncEngine` 传入流水线 | 用 `SyncEngineTests` 中的 `RecordingSource` 方式验证 |

### C6 截图、打包、报告
1. 新增截图路由：`ride:chart`（滚动到双轴曲线；如果滚动不好实现，就把曲线卡片放在详情的指标卡片之后，确保第一屏能看到）、`ride:laps`（一次有分圈的 FIT 骑行）、`metric:ef`、`ftp-history`、`settings:sources`。合成场景中，至少保证一次 FIT 骑行带 3 个以上分圈（如果现在没有，在 FIT 编码器生成合成文件时加上；**这可能改变黄金快照**，要在 DECISIONS 中说明）。
2. 运行 `scripts/screenshots.sh`，**逐张打开**新增路由的浅色和深色截图（共 10 张），以及 `ride`、`cardio` 的截图，检查：曲线没有连成直线的假数据、右轴的心率刻度与左轴对得上、分圈表的数值加起来与整次骑行一致、没有英文日期、深色模式可读。在 `BUILD-REPORT.md` 中逐张写下检查结论。
3. 版本号改为 `1.3.0`（build 6），四个 target 保持一致。运行 `scripts/package-ipa.sh`，确认生成 `dist/Vigor-1.3.0.ipa`，并且里面包含手表 App 和两个小组件扩展。
4. 在 `docs/BUILD-REPORT.md` 中追加“M6 补完”一节：完成清单、测试数、截图结论、DECISIONS 新编号范围、仍未验证的项。在 `DECISIONS.md` 中把 D-125 标注为“已由 M6 补完处理”，并逐项写明处理方式。

## 3. 完成标准
- [ ] C1–C6 在 `BUILD-PROGRESS.md` 中全部为 ✅（⚠️ 要有原因）
- [ ] 全部包的测试通过；黄金快照如有变化，已在 DECISIONS 中说明原因
- [ ] iOS（含手表与小组件）与 watchOS 构建都是 0 个 error
- [ ] 截图已逐张检查并记录结论
- [ ] `dist/Vigor-1.3.0.ipa` 已生成，包含手表 App 和两个小组件扩展
- [ ] 所有改动都已提交到本地 git（不包括 `docs/prompts/M6-cycling-build-prompt.md`）

## 4. 汇报内容
结束时汇报：C1–C6 每项的状态、测试通过数、所有 ⚠️ / ❌ 项及原因、截图检查结论、IPA 路径与其中包含的 bundle。如果中途有后台命令（例如截图脚本），**等它结束后继续做完剩下的步骤**，不要在等待时结束这一轮。
