# 施工任务：元气 Vigor · M1–M5 一次性完成

你是一名资深 iOS / watchOS 工程师。M0 已经完成，代码在 `/Users/zxz/Vibecoding/whoop`。你的任务是**一口气把 M1–M5 全部做完**：从算法、持久化、后台同步，到全部界面、手表、小组件、AI 教练、备份，最后导出可以安装的 IPA。

这是一个很长的任务。请严格按 §3 的阶段顺序推进，每个阶段都要“实现 → 测试 → 构建 → 提交 → 更新进度文件”，然后**直接进入下一阶段，不要停下来等确认**。只有 §2 中列出的硬阻塞才允许停止。

---

## 0. 开工前必读

1. 完整阅读 `docs/PRD.md`（v0.2，约 800 行）。**PRD 是功能与算法的唯一规格来源**。本文档只补充三类内容：执行顺序、工程约定、PRD 没写清楚之处的裁决（§4）。两者冲突时，以本文 §4 为准。
2. 阅读 `docs/M0-REPORT.md`，了解 M0 的现状和偏离项。
3. 浏览现有代码：`Packages/VigorScoring`、`Packages/VigorHealth`、`App/`。
4. 如果 `docs/BUILD-PROGRESS.md` 已经存在，说明你是在**中断后继续**：读它，从第一个未完成的阶段接着做，不要重做已提交的阶段。

## 1. 环境事实（已核实）

- Xcode 27.1，路径 `/Applications/Xcode.app`；许可协议已接受。`xcode-select` 指向 CommandLineTools，所以**每条** `xcodebuild` / `xcrun` / `swift` 命令前都要加：
  ```bash
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  ```
- iOS SDK 27.1，watchOS SDK 27.0，Swift 6.4，XcodeGen 2.43.0。部署目标：iOS 26.0 / watchOS 26.0。
- 可用的模拟器：iPhone 17 Pro（iOS 26.5）。手表模拟器先用 `xcrun simctl list devices available | grep -i watch` 查看，如果没有，只做构建验证。
- SDK 中已确认存在：`FoundationModels`、`WidgetKit`、`AppIntents`、`WatchConnectivity`、`BackgroundTasks` 框架；`HKHeartbeatSeriesQueryDescriptor`（元素字段为 `timeIntervalSinceStart`、`precededByGap`）；`SystemLanguageModel.default.availability`、`LanguageModelSession`。
- **不确定某个 API 时不要猜**，去 SDK 中查：
  ```bash
  SDK=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks
  grep -n "关键字" $SDK/<框架>.framework/Modules/<框架>.swiftmodule/arm64e-apple-ios.swiftinterface
  ```
  watchOS 的对应路径为 `WatchOS.platform/Developer/SDKs/WatchOS.sdk`，接口文件名为 `arm64_32-apple-watchos.swiftinterface`（以实际 `ls` 结果为准）。
- **分发方式**：用户在 iPhone 上用“全能签”加企业证书**重签名**安装。所以我们只需要产出一个**未用正式证书签名**的 IPA（具体做法见阶段 9）；不要配置任何正式签名，也不要找描述文件。

## 2. 硬性规则

1. 只用 Apple 一方框架，**不引入任何第三方依赖**（Python 也不用；分析工具全部用 Swift）。
2. Swift 6 语言模式 + 完整并发检查。不允许为消除并发警告而使用 `@unchecked Sendable` 或 `nonisolated(unsafe)`，除非在 `docs/DECISIONS.md` 中写明原因。SwiftData 的写操作放在 `@ModelActor` 中。
3. `VigorScoring` 只能依赖 Foundation，全部是纯函数或值类型；**所有“当前时间”都通过参数 `now: Date` 传入**，禁止在其中调用 `Date()`。
4. 界面文案使用简体中文，代码标识符使用英文。
5. **不修改 `docs/PRD.md`**。所有偏离、裁决、取舍都记录到 `docs/DECISIONS.md`（格式：编号、阶段、内容、原因）。
6. 测试使用 Swift Testing（`import Testing`），期望值必须精确；**测试不通过时，修改实现，绝不放宽断言**。如果你确信是本文给出的期望值错了，把推导过程写进 `DECISIONS.md` 之后才能改。
7. 每个阶段结束时必须：两个测试命令都通过 → iOS 模拟器构建 0 个 error → `git commit` → 更新 `docs/BUILD-PROGRESS.md`。
8. **硬阻塞（只有这些情况允许停止）**：Xcode 许可协议或工具链缺失；同一个编译错误连续修 3 次失败，而且无法通过缩小范围绕开。遇到其他问题时，选最简单、可逆的做法，记进 `DECISIONS.md` 后继续。
9. **某个功能实在做不出来时**（例如某个 API 在 SDK 中不存在），降级实现或者留出清晰的占位界面，记进 `DECISIONS.md`，然后继续推进，不要卡在一处。
10. 不要 push，也不要添加远程仓库。提交信息使用英文 Conventional Commits 格式。

## 3. 阶段总览

| 阶段 | 内容 | 对应 PRD |
|---|---|---|
| 1 | 数据层升级：快照 v2、实时数据源扩展、合成场景 v2、心跳缓存 | §2、§8.4 |
| 2 | 夜间算法 v2：会话拼装、RR 清洗、三种 HRV 模式、静息心率、生命体征 | §5.2–§5.5 |
| 3 | 基线、质量、恢复（含 Shapley）、睡眠、生病预警、评分流水线 | §5.6–§5.9、§5.12.1、§5.13 |
| 4 | 负荷：分钟心率时间线、TRIMP、目标、ACWR、空窗估算、压力、训练 | §5.10、§5.11、§5.12.2 |
| 5 | 持久化、同步引擎、后台、通知、`vigor-replay`、黄金快照 | §5.13、§5.14、§8 |
| 6 | 设计系统 + 全部主界面（M2 范围）+ 设置 + 实验室升级 | §6.1–§6.4、§6.6、§6.11、§6.12、§7 |
| 7 | 日志与洞察、身体年龄、心肺适能、报告 | §6.5、§6.7、§5.12.2 |
| 8 | 手表 App、小组件、复杂功能、App Intents | §6.8、§6.9 |
| 9 | AI 教练、备份、校准工具、诊断页、打包 IPA、最终报告 | §6.10、§9.4、§5.8.5、§5.14 |

---

## 4. 裁决与补充规格（PRD 未写清楚的部分）

### 4.1 工程结构（在 PRD §8.1 的基础上调整）
```
Packages/
  VigorScoring   纯算法（已有，扩展）
  VigorHealth    HealthKit 读取、快照、合成场景、心跳缓存（已有，扩展）
  VigorStore     SwiftData 模型、ModelActor 仓储、共享状态文件
  VigorEngine    编排：同步 → 特征 → 评分 → 持久化 → 通知；依赖上面三个包
  VigorDesign    设计令牌与通用组件（iOS + watchOS）
  VigorCoach     AI 教练：Foundation Models + Claude API 适配
Tools/VigorReplay  SwiftPM 可执行包，产物名为 vigor-replay
App/             iOS App
Watch/           watchOS App
Widgets/         iOS 小组件扩展
WatchWidgets/    watchOS 小组件扩展（复杂功能）
```
新增 `VigorEngine` 是因为编排需要同时依赖 Health、Scoring、Store 三个包；把这一条记入 DECISIONS。

### 4.2 评分流水线 = 对全部历史的纯函数
- `ScoringPipeline.run(_ input: PipelineInput) -> PipelineOutput` 放在 `VigorScoring` 中，是确定性的纯函数。
- `PipelineInput` 包含：`HealthDataset`（快照 v2 的领域数据）、日志条目、手动覆盖（睡眠修正、排除夜、最大心率、基础睡眠需求）、`ScoringConfig`、`now`、`calendar`。
- `PipelineOutput` 包含：每晚的 `NightFeatures`、每个 `Cycle` 的结果（含 Shapley、状态、各分项）、基线时间序列、趋势状态、负荷、训练汇总。
- 180 晚的全量计算应在 1 秒以内完成（在测试中断言 < 2 秒）。**重算 = 重新跑一次流水线**，增量只发生在 HealthKit 的读取层。
- “锁定”状态（PRD §5.13）由 `VigorEngine` 在持久化时实现：已锁定周期的记录只在 `configVersion` 变化或用户手动触发时才覆盖。

### 4.3 心跳缓存
heartbeat 序列读取很慢，原始节拍按 HK UUID 缓存在 `Application Support/HeartbeatCache/`（二进制：Float64 时间戳 + UInt8 间隙标记），删除事件到来时同步删除。这与 PRD“原始数据不复制”的原则有偏离，属于必要的工程取舍，记入 DECISIONS。

### 4.4 夜晚归属
- 会话中点的当地时间如果落在 [15:00, 19:00)，就不可能是主睡眠。
- 夜晚键 `nightKey` = 当地日期（中点 − 15 小时）。例如中点在 D 日 19:00 到 D+1 日 14:59 之间的会话都属于“D 夜”。
- 周期 N = 第 N 晚主睡眠的入睡时刻 → 下一个主睡眠的入睡时刻；最后一个周期是开放的（结束时间为 nil）。

### 4.5 晨测的识别
满足以下全部条件的 heartbeat 序列算作晨测：起点在 (醒来时刻, 醒来时刻 + 60 分钟] 之内，而且与某条 `mindfulSession` 样本在时间上重叠。不满足的醒后序列直接忽略（既不算夜间，也不算晨测）。

### 4.6 人群先验（PRD §5.6 冷启动，占位值，放在 `ScoringConfig.priors` 中）
| 指标 | μ 先验 | σ 先验 |
|---|---|---|
| 夜间 RMSSD（ms，按年龄段：<30 / 30–39 / 40–49 / 50–59 / ≥60） | 55 / 45 / 36 / 30 / 26（取 ln 后使用） | ln 单位 0.30 |
| 晨测 RMSSD | 夜间先验 × 0.8 | 0.30 |
| 夜间 SDNN（ms，同上年龄段） | 60 / 52 / 45 / 40 / 35（取 ln） | 0.30 |
| 夜间静息心率 | 男 55，女 58，其他 56 | 5 |
| 呼吸率 | 14.5 | 1.2 |
| 手腕温度 | 不使用先验 μ，n = 0 时 Δt 记为 0 | 0.25 |
| 血氧（%） | 96.5 | 1.0 |
| 睡着时长 | 7.0 h | 0.6 h |
| 修复性睡眠时长 | 2.6 h | 0.5 h |
| 入睡耗时 | 15 分钟 | 8 分钟 |

年龄未知时按 30–39 岁处理。收缩完成后再应用 σ 下限。

### 4.7 其他常量（放在 `ScoringConfig` 中）
- 呼吸紊乱“升高”阈值：`breathingDisturbanceElevated = 10`（单位以 HealthKit 实际返回的为准）。**快照中保存原始值和单位字符串**，等真实数据到了再校准。
- 分钟心率空窗估算（PRD §2.2 约束 B）：用最近 28 天中心率与活动能量同时存在的分钟，拟合线性回归 `HR = a + b · kcal/min`；只有样本 ≥ 500 且 R² ≥ 0.3 时才启用，否则空窗按静息处理。
- 压力（0–3）：在没有训练、步数 < 100 且至少有 2 个心率点的 15 分钟窗口内，计算 `elev = (平均心率 − 夜间静息心率 μ) / 夜间静息心率 μ`，`stress = clamp(elev / 0.10, 0, 3)`；当日 z_hrv < −1 时再加 0.5（上限仍为 3）。
- 身体年龄（示意性系数，待校准）：
  ```
  偏移年 = −0.6·(VO2max − VO2参考) + 0.25·(夜间静息心率μ − 60) − 4·(ln RMSSD μ − ln 夜间先验) − 0.05·(SRI − 75) − 0.0004·(日均步数 − 8000) − 0.02·(每周 Z2+ 分钟 − 150)
  ```
  结果截断在 ±15 年。VO2 参考值（男，按年龄段 <30 / 30–39 / 40–49 / 50–59 / ≥60）：45 / 43 / 41 / 38 / 35；女性各减 6。缺项时该项按 0 计，并在界面上列出缺了哪些。
- 心肺适能趋势：VO2max 的 90 天线性斜率 + 1 分钟心率恢复的 90 天中位数变化。“同配速心率”不做，记入 DECISIONS。
- 统计函数（放在 `VigorScoring/Stats/`）：加权中位数（按值排序后，取累计权重首次 ≥ 总权重 50% 的那个值）、百分位（线性插值，等同于 numpy 的默认方法）、MAD、Spearman 相关、Welch t 检验（p 值通过正则化不完全 Beta 函数计算 Student t 分布的 CDF）、岭回归（小矩阵用 Cholesky 分解求解）、分段线性回归（网格搜索拐点）、环形统计。

### 4.8 合成场景 v2（替代 M0 的合成快照，测试和模拟器演示都靠它）
`SyntheticScenario.make(nights: Int = 120, seed: UInt64 = 42, endingAt: Date, calendar: Calendar) -> SyntheticScenario`，返回 `snapshot`（快照 v2）、`journal`（合成日志）和 `truth`（注入事件清单，供测试断言）。在 M0 已有规则的基础上增加：
- **日间**：醒着时约每 5 分钟一个心率点（65–95）；每 5 分钟一条活动能量和步数样本。
- **训练**：每周 3–4 次，每次 30–75 分钟，类型为跑步、骑行或力量；训练期间每 5 秒一个心率点（130–170），并带有心率恢复样本。
- **多来源**：分期样本来自 Apple Watch；`inBed` 样本来自 iPhone（上床时刻比入睡早 5–25 分钟）。另外每 10 晚中有 1 晚，额外注入一条与手表分期重叠的“其他 App”分期样本，用来测试来源优先级。
- **日志与因果**：约 15% 的日子标记“饮酒”，饮酒当晚的 RMSSD × 0.82、夜间静息心率 + 4；约 10% 的日子标记“晚餐过晚”，最低心率出现在后 1/3 夜。
- **生病事件**：倒数第 20、19 晚，温度 +0.7 °C、呼吸率 +1.5、RMSSD × 0.7、静息心率 + 6。
- **小睡**：每 7 天中有 1 天，14:00 左右小睡 25 分钟。
- **未佩戴**：倒数第 50 晚完全没有数据。
- 其余的夜间规则（无序列的夜晚、晨测）沿用 M0 中按序号判断的方式，晨测要同时生成对应的 `mindfulSession`。
- 所有时间戳对齐到整秒（M0 的经验）。

---

## 5. 各阶段详细要求

### 阶段 1：数据层升级

1. **快照 schema v2**（`HealthSnapshot` 升级，`schemaVersion = 2`；解码时能读取 v1，缺失的字段填空数组）：
   - 样本增加来源信息：`sourceBundleID`、`sourceName`、`productType`、`creationDate`，以及时区元数据 `timeZoneID`（如果有的话）。分期样本只靠这些字段判断来源优先级（PRD §5.2 步骤 1–2），删掉 M0 的 `sourceIsWatch`，或者改成计算属性。
   - 新增类型：`inBed`（单独的数组）、`mindfulSessions`、`workouts`（类型、起止时间、能量、距离、HK UUID）、`activeEnergy`、`steps`、`vo2Max`、`heartRateRecovery`、`breathingDisturbances`（值 + 单位字符串）、`timeInDaylight`、`dietaryCaffeine`、`alcoholicBeverages`、`stateOfMind`（效价、标签）。
   - `UserProfile` 增加身高、体重。
2. **`LiveHealthDataSource`** 增加以上全部类型的读取；授权范围同步扩大（PRD §2.3，写入权限为 `mindfulSession` 和 `workout`）。
3. **增量读取**：新增 `HealthSyncReader`，基于 `HKAnchoredObjectQueryDescriptor`。每种类型的锚点持久化（序列化 `HKQueryAnchor`，存入 `UserDefaults`），返回新增样本和已删除 UUID 的集合。
4. **心跳缓存**（§4.3）。
5. **合成场景 v2**（§4.8）。保留 `SyntheticSnapshot.make` 作为兼容入口，内部转调 v2。
6. **测试**：v1 → v2 解码；v2 往返相等；合成场景的确定性；`truth` 中列出的事件确实出现在数据里（例如生病夜的温度确实偏高）。

### 阶段 2：夜间算法 v2（严格按 PRD §5.2–§5.5 重写）

M0 的实现按旧规格编写，与 PRD v0.2 存在差异（见 `M0-REPORT.md` §4）。本阶段把它们全部替换为 PRD v0.2 的规则：
- `SleepSessionBuilder`：来源优先级、同源重叠、45 / 120 分钟合并 + 夜间窗口 + 长清醒标记、主睡眠 / 小睡 / 夜班规则、边界与上床时刻、佩戴检测、时区、手动修正覆盖层、分期使用原则（觉醒 ≥ 2 分钟；hypnogram 的显示用合并，单独写一个函数）。
- `RRProcessor` v2：三层伪迹过滤；删除而不插值；整段验收（≥ 40 个 RR、剔除率 ≤ 20%、时长 ≥ 45 秒）；每段特征；上下文标注；扰动检测（段内平均心率 > 夜间静息心率 × 1.15 时丢弃——注意这里依赖 §5.4，先算出静息心率，再回头过滤）。
- `NightHRVAggregator` v2：权重 q × p × s；≥ 3 段取加权中位数，2 段取加权平均，1 段直接采用；加权 IQR；三种模式分别输出。
- `NightRestingHR` v2：样本池包含序列平均心率；取 P10；最低心率出现时刻（15 分钟滑动中位数）。
- 生命体征 §5.5。
- 新的输出类型 `NightFeatures` 覆盖 PRD §8.3 中列出的全部字段（`HRVWindow` 数组也要有）。
- 删除 M0 中已被取代的类型，同步更新实验室页面，保证编译通过。

**本阶段必须有的测试（期望值精确）**：
| 测试 | 期望 |
|---|---|
| 来源优先级 | 同一时段手表和其他 App 都有分期时，只采用手表的 |
| 合并 | 间隔 40 分钟 → 合并；凌晨 02:00 间隔 90 分钟 → 合并并标记长清醒；14:00 间隔 90 分钟 → 拆分 |
| 主睡眠 | 中点在 16:00 的 4 小时会话不能成为主睡眠；夜班场景（只有一个白天 5 小时的会话）→ 它成为主睡眠 |
| 觉醒次数 | 清醒段 [1 分钟, 3 分钟, 2 分钟] → 2 次 |
| 局部中位数 | 一串 1000 ms 中间夹一个 1300 → 1300 被剔除，且不产生跨越它的 Δ |
| 早搏 | 一串 1000 ms 中出现 750 紧跟 1250 → 两拍都被剔除 |
| 整段验收 | 39 个有效 RR → 无效；时长 44 秒 → 无效 |
| 加权中位数 | 值 [ln20, ln30, ln40]，权重 [1, 1, 3] → ln40 |
| 两段 | 两段权重相同，RMSSD 为 20 和 40 → exp(mean(ln)) = √800 ≈ 28.2843 |
| P10 | 样本 1…20 → 2.9 |
| 扰动 | 段内平均心率 = 静息心率 × 1.2 → 丢弃 |
| 晨测识别 | 醒后 20 分钟的序列与正念记录重叠 → 晨测；不重叠 → 忽略 |

### 阶段 3：基线、质量、恢复、睡眠、生病预警、流水线

按 PRD §5.6–§5.9、§5.12.1、§5.13 实现，再加上 §4.2 的流水线。要点：
- 基线严格**不使用当晚及以后的数据**；σ 下限；冷启动收缩（§4.6）；有效夜的判定；自动排除（生病、跨 3 个以上时区后的头 2 晚）与手动排除；双时间尺度趋势与 CV 判定。
- 质量分 Q 的四个分量；不出分的条件。
- 恢复：z 截断、连续扣分、缺失时重新分配权重、矛盾信号、生病封顶、**精确 Shapley**。
- 睡眠：基础指标、SRI、环形统计、负债递推、需求构成、睡眠分、作息建议（三档 + 渐进调整）、基础需求个性化（方法 A 和 B）。
- 生病预警：注意 / 可能不适两级、混杂因素、自动排除基线。
- 分数状态机：等待 → 初步 → 最终 → 锁定（基于 `now` 判断）；输入哈希。

**本阶段必须有的测试**（e 为自然常数；容差为 ±0.001，另有说明的除外）：
| 测试 | 期望 |
|---|---|
| raw = 0 | Recovery = 100 / (1 + e^−0.35) = **58.662** |
| 只有 z_hrv = 1，其余为 0 | Recovery = **75.399**；Shapley(hrv) = **16.737**；全部贡献之和 = Recovery − 58.662 |
| z_rhr 缺失，z_hrv = 1，z_sleep = 0 | 权重变为 0.7333 / 0.2667，Recovery = **79.85**（±0.05） |
| 任意随机输入（属性测试，100 组） | Shapley 之和 = Recovery − 58.662（±1e-9） |
| 矛盾信号 | z_hrv = 2.5，z_rhr = −1.5 → z_hrv 按 1 计算，并打上“信号矛盾”标记 |
| 生病封顶 | “可能不适”时 Recovery ≤ 33 |
| pen_temp | Δt = 0.8 → 0.8；Δt = 1.5 → 1.2（封顶） |
| pen_spo2 | 中位数 93 → 0.2；中位数 90 → 0.4（封顶） |
| σ 下限 | 30 晚 ln RMSSD 完全相同 → σ = 0.06 |
| 不用未来数据 | 第 N 晚的基线与第 N 晚自身的值无关（改变第 N 晚的值，基线不变） |
| 冷启动 | n = 0 → μ = 先验；n = 7 → μ = (先验 + 个人) / 2 |
| 负债递推 | 基础 7.5 h，负荷 0，无小睡，D_prev = 0，TST = 6.5 h → D = 1.0 h，次晚需求 = 7.8 h；D 不低于 0、不超过 10 h |
| 环形均值 | 23:50 与 00:10 → 00:00；完全相同的时刻 → 环形标准差 = 0 |
| SRI | 7 天作息完全相同 → 100；不足 5 天 → nil |
| 生病预警 | 用合成场景跑流水线：倒数第 20、19 晚被判为“可能不适”，并被排除出基线；饮酒夜不会被排除 |
| 流水线性能 | 120 晚合成场景全量计算 < 2 秒 |
| 分区分布 | 合成场景的分区比例，每一区都在 15%–65% 之间（只用来防止参数离谱） |

### 阶段 4：负荷

按 PRD §5.10、§5.11 和本文 §4.7 实现分钟心率时间线、TRIMP、负荷映射、训练负荷、区间分布、目标区间、ACWR、空窗估算、压力、最大心率的自动上调（30 秒滑动均值）。

**测试**：
| 测试 | 期望 |
|---|---|
| 负荷映射 | TRIMP 20 → **5.823**；87 → **12.042**；300 → **18.200**；600 → **21**（封顶） |
| 每分钟 TRIMP | 男，x = 0.5 → **0.83574**；女，x = 0.5 → **0.99109**；x = 0.2 → 0 |
| 插值 | 两个心率点相隔 10 分钟 → 线性插值；相隔 20 分钟 → 中间按空窗规则处理 |
| 目标区间 | 绿 → 14–18；ACWR = 1.4 时 → 12–16 |
| 空窗回归 | 样本不足 500 个时不启用 |
| 最大心率 | 训练中 30 秒均值达到 195，而公式值为 185 → HRmax 更新为 195 |

### 阶段 5：持久化、同步引擎、后台、通知、回放工具

1. **VigorStore**：按 PRD §8.3 建立 SwiftData 模型。嵌套结构（Shapley 贡献、需求构成、`HRVWindow` 数组、分钟心率）以 JSON `Data` 属性保存；需要查询的标量（日期、分数、状态、版本）作为独立属性。所有写操作都通过 `@ModelActor` 仓储完成。另外写一个**共享状态文件** `shared-state.json`（今日三个分数、状态、目标区间、建议入睡时间、更新时间），供小组件和手表读取：App Group 容器可用时写在容器里，否则写在 App 自己的目录中，并记录“App Group 不可用”。
2. **VigorEngine**：
   - `SyncEngine`：首次启动导入历史（默认 180 天，每次 7 天分批，heartbeat 单独排队，显示进度）；之后用锚点增量读取。
   - 读取完成后：组装 `HealthDataset`（数据库 + 缓存）→ 跑流水线 → 按锁定规则写库 → 写共享状态 → 刷新小组件（`WidgetCenter.shared.reloadAllTimelines()`）→ 通过 WatchConnectivity 推送 → 视情况发送通知。
   - 后台：对睡眠、HRV、心率、心跳序列、训练、手腕温度、呼吸率调用 `HKObserverQuery` + `enableBackgroundDelivery`（睡眠和训练用 `.immediate`，其余用 `.hourly`）；`BGProcessingTask`（标识符 `com.example.vigor.nightly`）每天凌晨运行一次全量重算。在 Info.plist 中加上 `BGTaskSchedulerPermittedIdentifiers`，`UIBackgroundModes` 加上 `processing` 和 `fetch`。
   - **任何授权或后台注册失败都不能导致崩溃**：错误要保存下来，供诊断页（阶段 9）显示。
   - 通知（本地通知，按 PRD §6.9 和 §5.13）：恢复分数已生成（初步且质量 ≥ 中时发，否则等到最终）、分数更新（变化 ≥ 5）、作息提醒、晨测提醒（可选）、生病预警、周报。每个周期每种通知最多发一次。
   - 数据源切换：实时 / 合成 / 导入快照，三种模式共用同一条引擎路径。
3. **`Tools/VigorReplay`**：命令行工具 `vigor-replay <snapshot.json> [--out dir] [--config config.json] [--now ISO8601]`，输出 `nights.csv`、`cycles.csv`、`baselines.csv`；`--synthetic` 参数直接使用合成场景。
4. **黄金快照测试**：固定 `seed = 42`、`endingAt = 2026-10-01T00:00:00+08:00`、`now = endingAt`，生成合成场景并跑流水线，把关键列（日期、恢复、负荷、睡眠分、HRV、质量）序列化成 CSV，存到 `VigorScoring` 测试资源中，测试时逐行比对。提供 `vigor-replay --update-golden` 用于更新黄金文件。**每次之后的阶段如果导致黄金文件变化，必须在 `DECISIONS.md` 中说明原因。**
5. **测试**：仓储的读写往返；锁定周期在配置不变时不被覆盖；共享状态文件的编解码；`vigor-replay` 运行后输出的 CSV 行数正确（构建后用命令行实际跑一次）。

### 阶段 6：设计系统 + 主界面

1. **VigorDesign**：PRD §7.2 的令牌（颜色用系统语义色，同时支持深色模式）；PRD §7.3 的全部组件：`ScoreRing`、`MetricCard`、`RangeChart`（D / W / M / 6M / Y 切换 + 基线范围带 + 拖动选中）、`ContributionWaterfall`、`Hypnogram`（含心率叠加）、`HRTimeline`、`QualityBadge`；另外加上 `StateBanner`（未佩戴、校准中、质量低、生病）和 `SectionCard`（Apple Health 式卡片容器）。每个组件都要配 `#Preview`，覆盖多种状态。
2. **TabBar**（PRD §4）：摘要 / 睡眠 / 负荷 / 日志 / 浏览。实验室和设置从摘要页右上角的头像菜单进入。
3. 按 PRD §6.1–§6.4、§6.6、§6.11、§6.12 实现页面：摘要、恢复详情、睡眠页、负荷页（含训练详情）、浏览 + 通用指标详情、设置、实验室升级（HRV 段表、基线曲线、Shapley、负债递推、质量明细、参数面板 + 全量重算 + 新旧版本对比、消融对比、导出 CSV / JSON / 快照）。日志页本阶段先放占位，阶段 7 完成。
4. **Onboarding**（PRD §2.3）：检查清单 + 授权 + 历史导入进度；模拟器中跳过授权，直接使用合成场景。
5. **截图路由**：支持启动参数 `-VigorSource synthetic|live` 和 `-VigorRoute <路由>`。路由包括：`summary`、`recovery`、`sleep`、`strain`、`workout`、`journal`、`browse`、`metric:hrv`、`metric:rhr`、`settings`、`lab`、`lab:night`、`report`、`coach`、`diagnostics`、`onboarding`。启动后直接打开对应页面，用于自动截图。
6. 编写 `scripts/screenshots.sh`：构建 → 安装到模拟器 → 依次用每个路由启动 → 截图保存到 `docs/screenshots/<路由>.png`，浅色和深色各一套（深色模式用 `xcrun simctl ui <UDID> appearance dark` 切换）。
7. **验证**：运行截图脚本，**逐张打开截图检查**：没有空白页、没有截断的文字、没有占位用的“TODO”、深色模式下文字可读。发现问题就修复，然后重新截图。

### 阶段 7：日志、洞察、身体年龄、心肺适能、报告

- 日志页（PRD §6.5）：问卷（默认题目 + 自定义题目，是否 / 数量两种题型）、HealthKit 自动填充项、主观精力 1–5、历史记录。醒来后的日志问卷通知。
- 影响洞察：Welch t 检验，两组各至少 5 个样本；指标为次日恢复、HRV、睡眠表现；按效应量排序；显示差值、置信区间和 p 值，文案要通俗（例如“饮酒后次日恢复平均低 14 分，差异明显”）。合成场景中“饮酒”必须排在第一位（在测试中断言）。
- 亮点（Highlights）与教练一句话的**模板版**（不依赖 AI）：根据规则生成，阶段 9 再加上 AI 润色。
- 身体年龄、心肺适能（§4.7），在浏览页中新增对应的指标入口。
- 报告（PRD §6.7）：周报和月报的数据由 `VigorScoring` 中的 `ReportBuilder` 纯函数生成，页面展示 + 周日晚上推送通知。
- **测试**：Student t 分布 CDF，t = 2.0、df = 10 时双侧 p = **0.07339**（±0.0005）；Welch 的自由度公式；Spearman：严格单调 → 1；合成场景中饮酒洞察排第一；`ReportBuilder` 的周边界。

### 阶段 8：手表、小组件、App Intents

1. **project.yml** 增加以下 target（写完后要检查构建产物的结构：`Vigor.app/Watch/VigorWatch.app`、`Vigor.app/PlugIns/VigorWidgets.appex`、`VigorWatch.app/PlugIns/VigorWatchWidgets.appex`）：
   - `VigorWatch`：watchOS application，Bundle ID `com.example.vigor.watchkitapp`，Info.plist 中设置 `WKApplication = true`、`WKCompanionAppBundleIdentifier = com.example.vigor`、`UIBackgroundModes = [workout-processing]`，HealthKit entitlement；iOS App 依赖这个 target（由 XcodeGen 自动嵌入）。
   - `VigorWidgets`：iOS app-extension（`com.apple.widgetkit-extension`），Bundle ID `com.example.vigor.widgets`。
   - `VigorWatchWidgets`：watchOS app-extension，Bundle ID `com.example.vigor.watchkitapp.widgets`，嵌入 `VigorWatch`。
   - 全部 target 都加上 App Group `group.com.example.vigor` 的 entitlement。
2. **手表 App**（PRD §6.8）：今日页（三个分数 + 当前累积负荷）；训练模式（`HKWorkoutSession` + `HKLiveWorkoutBuilder`，显示实时心率、区间、本次负荷、全天累积负荷；结束后保存）。实时负荷直接复用 `VigorScoring` 中的 TRIMP 函数。通过 WatchConnectivity 接收手机推送的共享状态；接收不到时显示上一次的缓存。
3. **复杂功能**：恢复环、负荷仪表、建议入睡时间，支持 accessoryCircular / accessoryRectangular / accessoryInline。
4. **iOS 小组件**：小尺寸（单个分数）、中尺寸（三个分数）、锁屏（accessoryCircular / accessoryRectangular）、建议入睡时间。数据来自共享状态文件；读不到时显示“打开元气以更新”。
5. **App Intents**：“今天恢复怎么样”、“今天负荷多少”、“今晚几点睡”，通过 `AppShortcutsProvider` 注册中文短语。
6. **验证**：iOS 构建（会连带构建手表和小组件）、watchOS 模拟器构建（`-destination 'generic/platform=watchOS Simulator'`）；有手表模拟器时截一张手表首页的图。

### 阶段 9：AI 教练、备份、校准、诊断、打包、报告

1. **VigorCoach**（PRD §6.10）：
   - `CoachProvider` 协议，两个实现：`OnDeviceCoach`（Foundation Models；先检查 `SystemLanguageModel.default.availability`）和 `ClaudeCoach`（URLSession 请求 `https://api.anthropic.com/v1/messages`，请求头为 `x-api-key` 和 `anthropic-version: 2023-06-01`；默认模型 `claude-haiku-5-5`，可以在设置中改；API key 存在钥匙串中）。
   - 自动选择：端侧可用就用端侧，否则在用户填了 key 时用 Claude，都没有时退回模板文案。
   - 输入只有**脱敏后的每日汇总 JSON**（分数、z-score、日志项、趋势状态；不含原始样本和时间戳精度以外的信息）。使用云端模型时，**发送前弹出预览**（PRD §9.3），用户确认后才发送。
   - 能力：润色教练一句话、生成周报和月报的总结、对话页（多轮问答，上下文为最近 30 天的汇总）。
2. **备份**（PRD §9.4）：导出 `.vigorbackup` 文件（日志、配置、覆盖项、派生数据），用 CryptoKit 的 AES-GCM 加密，密钥由用户密码经 CommonCrypto PBKDF2-SHA256 派生（迭代 200,000 次，随机盐）；可以导入恢复；通过 `fileExporter` 和 `fileImporter` 存取“文件”App。测试：加密 → 解密往返；密码错误时报错。
3. **校准工具**（PRD §5.8.5、§5.9.3、§5.14）：实验室中的岭回归权重拟合（按时间 70 / 30 切分，Spearman 相关系数提升 ≥ 0.05 才建议采用）、生成新的 configVersion 并全量重算、回滚、基础睡眠需求建议值、消融对比。
4. **诊断页**（路由 `diagnostics`，设置中也有入口）：显示 Bundle ID、版本号、HealthKit 是否可用、授权请求的结果或错误原文、后台推送注册结果、App Group 容器是否可用、WatchConnectivity 状态、最近一次同步的时间和错误。**这一页用来排查重签名后权限是否丢失**，所有错误都要显示原文。
5. **打包 IPA（供“全能签”重签名）**：
   ```bash
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   cd /Users/zxz/Vibecoding/whoop && xcodegen generate
   xcodebuild -project Vigor.xcodeproj -scheme Vigor -configuration Release \
     -destination 'generic/platform=iOS' -derivedDataPath build/ipa \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
   rm -rf build/Payload && mkdir -p build/Payload dist
   cp -R build/ipa/Build/Products/Release-iphoneos/Vigor.app build/Payload/
   ```
   然后对每个 bundle **由内到外**做 ad-hoc 签名，并嵌入各自的 entitlements，方便重签工具读取所需的权限：先签手表小组件 appex → 手表 App → iOS 小组件 appex → 主 App，每一步都执行 `codesign -f -s - --entitlements <对应的 .entitlements> <bundle 路径>`（嵌入的 framework 和 dylib 用 `codesign -f -s -` 签名，不带 entitlements）。最后：
   ```bash
   cd build && zip -qry ../dist/Vigor-<版本号>.ipa Payload && cd ..
   codesign -d --entitlements - build/Payload/Vigor.app   # 确认包含 healthkit
   ```
   版本号取 `CFBundleShortVersionString`，本次设为 `1.0.0`。
6. **最终报告** `docs/BUILD-REPORT.md`：
   - 逐阶段的完成清单（✅ / ⚠️ 只编译验证 / ❌），以及各阶段测试的通过数。
   - 截图索引（`docs/screenshots/`）。
   - `DECISIONS.md` 的摘要。
   - **未验证项**（必须明确写出）：真机 HealthKit 读取、后台推送、通知、手表训练模式、WatchConnectivity、小组件在真机上的数据刷新、Foundation Models 的可用性、全能签重签名后 HealthKit / App Group / 后台推送是否保留。
   - 给用户的真机验收清单：用全能签安装 → 打开诊断页截图 → 完成 onboarding → 第二天早上检查是否收到恢复分数通知 → 实验室导出快照发回。

---

## 6. 进度文件 `docs/BUILD-PROGRESS.md`

在阶段 1 开始前创建，每个阶段结束时更新，格式如下：
```
## 阶段 N：<名称> —— ✅ 完成 / 🚧 进行中
- 提交：<hash>
- 测试：VigorScoring X 个通过，VigorHealth Y 个通过，……
- 构建：iOS ✅  watchOS ✅/—
- 备注：<给“中断后继续的自己”看的关键信息>
```

## 7. 每个阶段的验证命令

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd /Users/zxz/Vibecoding/whoop
for p in Packages/*/ Tools/*/; do [ -f "$p/Package.swift" ] && (cd "$p" && swift test 2>&1 | tail -3); done
xcodegen generate
xcodebuild -project Vigor.xcodeproj -scheme Vigor -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build -quiet
```
没有测试目标的包，`swift test` 会报 “no tests found”，这是正常的；但只要包里有测试，就必须全部通过。阶段 6 及以后还要加跑截图脚本；阶段 8 及以后还要加跑 watchOS 构建。

## 8. 完成标准
- [ ] 阶段 1–9 在 `BUILD-PROGRESS.md` 中全部标记为 ✅（⚠️ 的项要有原因）
- [ ] 全部包的测试通过，黄金快照测试通过
- [ ] iOS（含手表和小组件）构建 0 个 error；watchOS 构建 0 个 error
- [ ] `docs/screenshots/` 中每个路由都有浅色和深色截图，并且已经人工检查过
- [ ] `dist/Vigor-1.0.0.ipa` 已生成，主 App 的 entitlements 中包含 HealthKit
- [ ] `docs/DECISIONS.md` 和 `docs/BUILD-REPORT.md` 已写好
- [ ] 所有改动都已在本地提交
