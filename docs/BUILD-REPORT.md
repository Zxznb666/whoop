# 元气 Vigor · M1–M5 施工报告

> 日期：2026-10-21 · 施工文档：`docs/prompts/M1-M5-build-prompt.md` · 决策记录：`docs/DECISIONS.md`（D-001 至 D-067）· 进度：`docs/BUILD-PROGRESS.md`

## 1. 完成情况

| 阶段 | 内容 | 状态 | 说明 |
|---|---|---|---|
| 1 | 数据层：快照 v2、增量读取、心跳缓存、合成场景 v2 | ✅ | 实时读取只做了编译验证（真机未验证） |
| 2 | 夜间算法 v2：睡眠会话、RR 清洗、三种 HRV 模式、静息心率 | ✅ | 施工文档 §5 阶段 2 的 14 项测试全部通过 |
| 3 | 基线、质量、恢复（含 Shapley）、睡眠、生病预警、流水线 | ✅ | 分区分布检验在阶段 4 后通过（D-038） |
| 4 | 负荷：分钟时间线、TRIMP、目标、ACWR、压力、最大心率 | ✅ | 合成数据的负荷与压力偏高（D-047） |
| 5 | 持久化、同步引擎、后台、通知、回放工具、黄金快照 | ✅ | 后台、通知、App Group 真机未验证；同步仍读取完整窗口（D-048） |
| 6 | 设计系统与主界面 | 🚧 | 实验室升级未做；只检查了 4/32 张截图 |
| 7 | 日志、洞察、身体年龄、心肺适能、报告 | 🚧 | 问卷界面、亮点、推送未做（D-060） |
| 8 | 手表、小组件、App Intents | ❌ | 只完成了 App Intents（D-064、D-066） |
| 9 | 教练、备份、校准、诊断、打包、报告 | 🚧 | 教练的 Claude 接入与备份、校准界面未做（D-061 至 D-063） |

## 2. 测试

| 包 / 工具 | 通过数 | 说明 |
|---|---|---|
| VigorScoring | 106 | 算法主体；含施工文档的全部数值锚点 |
| VigorHealth | 29 | 合成数据、快照编解码、心跳缓存、流水线（含性能测试） |
| VigorStore | 9 | SwiftData 内存容器、锁定规则、共享状态、备份加解密 |
| VigorEngine | 4 | 通知计划与去重 |
| VigorDesign | 2 | 设计令牌 |
| VigorCoach | 6 | 路由、模板、确认门控、Claude 请求与解析 |
| Tools/VigorReplay | 4 | 黄金快照、差异报告、CSV 行数、参数解析 |

全部测试在提交前均通过。性能测试断言计算线程的 CPU 时间 < 2 秒（D-039）；单独运行时墙钟约 1 秒（调试构建）。

## 3. 构建与打包

- iOS 模拟器（全 App，含所有包）：`BUILD SUCCEEDED`。
- 手表：未构建（D-066）。
- IPA：`dist/Vigor-1.0.0.ipa`（约 1.1 MB，版本 1.0.0，build 2）。
  - Release 构建：`xcodebuild -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`。
  - 对主 App 做 ad-hoc 签名并嵌入 `App/Vigor.entitlements`，确认包含 `com.apple.developer.healthkit` 与 `background-delivery`。
  - 包内没有扩展（没有 .appex）。
  - Info.plist 包含 `BGTaskSchedulerPermittedIdentifiers` 与 `UIBackgroundModes`（processing、fetch）。

## 4. 截图

`docs/screenshots/` 中有 16 个路由 × 浅色、深色，共 32 张（由 `scripts/screenshots.sh` 生成）。

已逐张检查：`summary-light`、`recovery-light`、`sleep-light`、`strain-light`、`journal-light`。
发现并修复的问题：演示数据的结束时间导致当日负荷为 0（已改为中午结束）；睡眠需求的堆叠条是叠加而不是堆叠（已修复）；负荷区间图为空时没有说明（已补充文字）；后台键被 XcodeGen 覆盖（已移入 `project.yml`）。

**未检查**：其余 27 张截图（包括全部深色模式截图）。这是本报告中最明确的未完成项，需要在真机或模拟器上逐张确认。

## 5. 未验证项（必须在真机上确认）

- HealthKit 实时读取（授权、睡眠、心率、心跳序列的读取耗时与进度）。
- 后台推送与 `BGProcessingTask`（凌晨全量重算）的触发时间。
- 通知的发送与去重。
- App Group 容器在全能签重签名后是否可用（决定小组件与手表能否读取共享状态）。
- 全能签重签名后，HealthKit、App Group 与后台推送是否保留。
- Foundation Models 在真机上的可用性（`SystemLanguageModel.default.isAvailable`）。
- 合成数据上的分布（负荷、压力偏高）是否符合真实情况（D-047），需要真实数据校准。

## 6. 给用户的真机验收清单

1. 用全能签安装 `dist/Vigor-1.0.0.ipa`。
2. 打开“诊断”页并截图（查看授权结果、后台注册、App Group 是否可用，以及错误原文）。
3. 完成“欢迎与授权”中的授权请求，并允许全部读取权限。
4. 等待首次导入完成，检查“摘要”页的三个分数与“浏览”页的身体年龄（标注为示意）。
5. 第二天早上检查是否收到“恢复分数已生成”的通知。
6. 打开“实验室”页（M0 保留），点击“导出快照”，把生成的 JSON 文件发回，用于 `vigor-replay` 复现。

## 7. 未完成清单（按优先级）

1. 阶段 8：watchOS App、训练模式、复杂功能、iOS 小组件（需要 target、App Group 与签名配置）。
2. 阶段 6：实验室升级（HRV 段表、基线曲线、Shapley、负债递推、参数面板、消融）；检查其余 27 张截图。
3. 阶段 7：问卷界面、醒来后的问卷通知、亮点与教练模板、心肺适能入口、报告推送。
4. 阶段 9：Claude 教练的 key 录入与确认弹窗、备份导入导出界面、校准界面与回滚。
5. 阶段 5：同步路径接入 `HealthSyncReader`（D-048）；通知的作息提醒、晨测提醒、周报。
6. 真机验证（第 5 节）。

## 补完（M5-completion，版本 1.1.0 build 4）

### 完成清单
| 项 | 内容 | 状态 |
|---|---|---|
| F1 | 日志问卷、题目设置、自动填充（只读）、醒来后提醒 | ✅ |
| F2 | 压力改用日间安静心率基线 | ✅（黄金快照未变，见 D-077） |
| F3 | 手表 App（今日页、训练模式）、iOS 与手表小组件、WatchConnectivity、App Intents 修正 | ✅ 构建；运行未验证 |
| F4 | 实验室：基线曲线、周期明细、HRV 段表、睡眠负债、消融、版本与回滚、校准、导出 | ✅（恢复权重采用未做，D-088） |
| F5 | 备份导入导出、Claude 教练（预览与确认）、周报 / 月报文字、亮点、心肺适能、周报推送 | ✅（端侧路径未在模拟器验证，D-092） |
| F6 | 负零显示、标签页根路由不压栈、生病预警 36 小时连续性 | ✅ |
| F7 | 睡眠时段修正、排除指定夜晚的持久化，传入流水线，备份包含 | ✅ |
| F8 | 截图、IPA、报告 | ✅（截图逐张检查 25 / 44） |

### 测试
全部包通过，合计 220 个：VigorScoring 120、VigorHealth 46、VigorStore 20、VigorEngine 17、VigorCoach 11、VigorDesign 2、VigorReplay 4（含黄金快照）。

### 构建
- iOS 模拟器（含手表与两个小组件）：0 个 error。
- watchOS 模拟器（`VigorWatch` scheme）：0 个 error，无警告。

### 截图检查（`scripts/screenshots.sh`，22 个路由 × 2 种外观 = 44 张）
逐张打开检查的 25 张：
- 浅色：摘要、恢复、日志、日志编辑、日志题目、备份与恢复、教练设置、排除指定夜晚、心肺适能、实验室（基线曲线区）、周报、教练、设置、睡眠、浏览、训练、负荷、HRV 详情、诊断、欢迎；实验室（夜晚路由）。
- 深色：摘要、教练、日志编辑、心肺适能。

检查结论：
- 没有空白页、截断或占位文字（除下列两点）。摘要页的第一张截图曾是空白（冷启动时数据尚未加载），重新截图后正常。
- **已修复**：教练页在数据加载完成前出现，“今日一句”停在“还没有数据”（`.task` 只执行一次）。改为按最新周期的醒来时间触发（`task(id:)`）。深色与浅色均已复查。
- **已修复**：心肺适能与设置的说明文字中出现了内部决策编号；已删除。排除页的说明曾写“也不推送”，但通知计划并不按排除过滤，已改为只说“不进入基线”。
- 深色模式下文字可读。
- 日期选择器显示英文月份（模拟器语言为英文，`DatePicker` 跟随系统语言），在中文设备上不会出现。
- 模拟器截图中的诊断页显示 HealthKit 授权错误与 App Group 不可用：这是未签名的模拟器构建的预期结果，不是故障。
- 实验室的版本对比、校准与导出区块位于页面下方，本次截图只覆盖到基线曲线。

未逐张检查的 19 张：浅色的 metric-rhr；深色的 recovery、sleep、strain、journal、journal-questions、backup、coach-settings、exclusions、lab、lab-night、report、settings、browse、workout、metric-hrv、metric-rhr、diagnostics、onboarding。这些页面在浅色模式下已经检查通过，深色模式的文字对比需要在真机上再看一遍。

### IPA
- 文件：`dist/Vigor-1.1.0.ipa`（版本 1.1.0，build 4）。
- 结构：`Payload/Vigor.app`（`com.example.vigor`）；`Watch/VigorWatch.app`（`com.example.vigor.watchkitapp`，WKApplication，WKCompanionAppBundleIdentifier = com.example.vigor）；`PlugIns/VigorWidgets.appex`（`com.example.vigor.widgets`）；`Watch/VigorWatch.app/PlugIns/VigorWatchWidgets.appex`（`com.example.vigor.watchkitapp.widgets`）。
- 签名：四个 bundle 均为 ad-hoc 签名；主 App 含 HealthKit、background-delivery 与 App Group；手表 App 与两个小组件分别含各自的 entitlements（App Group `group.com.example.vigor`）。
- `scripts/package-ipa.sh` 对手表与小组件的签名步骤使用了 `|| true`，所以签名失败会被吞掉。本次通过解包后逐个检查 entitlements 确认成功，但脚本本身仍应改为失败即退出。

### 仍未验证（需要真机或签名后的 App）
- 真机 HealthKit 读取、后台任务、通知投递（含日志提醒的延迟触发）。
- 手表：训练模式的心率、区间、TRIMP 与保存到“健康”；手表模拟器运行时在本机不可用（只有 watchOS 9.1，与当前 macOS 不兼容），因此没有手表截图。
- WatchConnectivity 的推送与接收；小组件与复杂功能的刷新。
- 重签名后 App Group 是否可用（代码已容忍不可用：显示“打开元气以更新”）。
- 端侧模型（FoundationModels）的周报总结。
- Claude 请求的真实返回（只做了请求构造与解析的测试，没有发出真实请求）。
- 实验室恢复权重的采用（未实现，D-088）。
- 排除的夜晚是否应抑制推送：通知计划目前没有按排除状态过滤（与 PRD 的“不推送”不一致，待决定）。
- 非训练日负荷偏高（D-047）保留，待真实数据校准。

## M6 骑行

### 完成情况（阶段 10–13）
| 阶段 | 内容 | 状态 |
|---|---|---|
| 10 | `VigorFIT`：FIT 解析器（头、CRC、压缩时间戳、定义消息、开发者字段、无效值）、测试编码器、`RideStream` | ✅（14 个测试） |
| 11 | 快照 v3、骑行分组（重叠 ≥ 50%）、分钟级去重（五级来源优先级）、功率补偿、骑行指标（NP / IF / TSS / FTP / 机械功 / 功率曲线 / EF / 有氧解耦）、PMC、流水线接入、合成场景 v3、黄金快照更新 | ✅（VigorScoring 151、VigorHealth 52 个测试中的骑行部分） |
| 12 | 导入（文件 App 多选、文件夹递归、分享面板“用元气打开”）、原始文件保存、存储去重、备份纳入、训练列表 / 骑行详情 / 负荷页卡片 / PMC / FTP 页 / 设置、截图路由 | ✅ 完成（界面有未做的部分，见下） |
| 13 | 版本 1.2.0（build 5），IPA 打包，本报告 | ✅ |

测试（`swift test`，各包）：VigorScoring 151、VigorFIT 14、VigorHealth 52、VigorStore 26、VigorEngine 17、VigorCoach 11、VigorDesign 2、VigorReplay 4，合计 **277 个通过**。
构建：iOS（`Vigor` scheme）0 个 error；watchOS（`VigorWatch` scheme）0 个 error。

### 审查修正（阶段 12 之后）
- **稀疏功率不是 0 W**（D-128、D-129）。原因：`powerWindow` 会返回窗口之前结束的样本，旧代码把它的值写进第 0 秒，导致一次没有功率的骑行显示 NP 32 W。现在只处理与骑行窗口重叠的样本；空档不超过 5 秒沿用前值、更长用本次平均功率，暂停为 0；覆盖率低于 50% 时不计算 NP、IF、TSS、功率区间、功率曲线，也不参与 FTP 与功率补偿，界面显示“功率数据不足”。
- **手表被动心率不再冒充训练心率**（D-130）。只有落在手表自己的训练内的手表样本才是 `watchWorkout`；落在 Garmin 训练内时同一分钟的 Garmin 心率优先。
- **中文日期**（D-133）：骑行页统一使用 zh_CN 格式。
- 合成场景第三类（只有 Garmin、无心率、无 FIT）本身没有功率数据（D-131）。

### 截图检查（8 张，逐张打开）
| 截图 | 检查结论 |
|---|---|
| `ride-light` | 2026年9月25日 10:25，心率带（FIT）+ 功率 FIT，已合并 2 个来源。NP 205 W、IF 1.02、TSS 152、机械功 1071 kJ、功体比 2.93 W/kg（205 ÷ 70 kg）、平均心率 142、EF 1.45（205 ÷ 142）、解耦 0.6%。Z3–Z6 有分钟数，Z1 为 0，与高强度骑行一致。数值互相一致，合理。 |
| `ride-dark` | 与浅色相同数值，仅配色不同。合理。 |
| `ride-garminOnly-light` | 2026年9月28日 10:33，无心率、无功率、1 个来源（其他 App 训练）。所有功率与心率指标显示“—”，有“建议导入 FIT”提示，功率曲线显示“这次骑行没有功率数据”。修正前这里曾显示 90 天最佳的柱状图，容易误解，已改掉。合理。 |
| `ride-garminOnly-dark` | 与浅色相同。合理。 |
| `pmc-light` | 体能管理：CTL 53.5、ATL 27.1、TSB 23.2，状态“状态新鲜”（TSB > +15）。CTL 从约 35 缓慢上升，ATL 在 25–110 之间波动，TSB 曲线与两者一致。合理。注：该截图在 iPhone 17 Pro Max 模拟器上拍摄（见下），首次截图被另一个会话的应用覆盖，已废弃重拍。 |
| `pmc-dark` | 与浅色相同数值。合理。 |
| `metric-ftp-light` | FTP 201 W，来源“自动估算（最近 90 天最佳 20 分钟 × 0.95）”，即 20 分钟最佳约 211 W × 0.95 ≈ 201，与下方曲线一致；EF 趋势稳定在 1.4–1.5；90 天最佳曲线 5 秒 ≈ 260、1 分钟 ≈ 240、5 分钟 ≈ 220、20 分钟 ≈ 210、60 分钟 ≈ 207，随时长单调下降。合理。 |
| `metric-ftp-dark` | 与浅色相同。合理。 |

截图设备：`ride`、`ride:garminOnly` 的浅色与深色中，`ride` 两张在 iPhone 17 Pro 上拍摄，`ride:garminOnly` 与 `pmc`、`metric:ftp` 在 iPhone 17 Pro Max 上拍摄（17 Pro 模拟器同时被另一个会话占用，拍摄时被其他应用覆盖）。两台设备的截图布局略有不同。其余路由的截图（`scripts/screenshots.sh` 的 22 个路由）保留为 M5 时的版本：它们没有重新拍摄，因此不反映骑行相关的新增区块（负荷页、训练列表、浏览页、设置页）。

### 数据与口径（D-103 至 D-133）
- FIT 解析：按 SDK 规则手写，编码器只在测试中；CRC、压缩时间戳、大端、开发者字段、无效值均有测试。
- 骑行分组：重叠时长 ÷ 较短者 ≥ 50% 归为一次骑行（并查集）。
- 去重：同一分钟只取最高优先级来源的均值（FIT > 手表训练 > 其他训练 > 手表被动 > 其他）。
- 功率补偿：连续 ≥ 5 分钟无心率且有功率时，优先个人回归模型，其次 k·TSS，都不可用时标记“负荷可能低估”。
- 黄金快照：随骑行负荷、睡眠需求与分钟去重的修正多次更新，变化量与原因见 D-117 与 D-132。
- 流水线耗时（调试构建）约 1.8 秒，断言仍为 < 2 秒（D-116）；余量较小，在更慢的机器上需要关注。

### IPA
- 文件：`dist/Vigor-1.2.0.ipa`（6.2 MB，版本 1.2.0，build 5）。
- 结构（已解包核对）：`Payload/Vigor.app`（`com.example.vigor`，1.2.0 (5)）；`Watch/VigorWatch.app`（`com.example.vigor.watchkitapp`，1.2.0 (5)）；`PlugIns/VigorWidgets.appex`（`com.example.vigor.widgets`）；`Watch/VigorWatch.app/PlugIns/VigorWatchWidgets.appex`（`com.example.vigor.watchkitapp.widgets`）。
- 主 App 的 entitlements 含 HealthKit（`scripts/package-ipa.sh` 已检查）。
- 签名为 ad-hoc，由用户用“全能签”重签名后安装。

### 仍未验证（需要真机或签名后的 App）
- **Garmin 写入的训练到底有没有心率样本**：代码同时兼容有与无两种情况；合成数据覆盖了两种情况，真实数据未知。
- **Edge 830 通过 USB 连接 iPhone 能否识别 `Garmin/Activity` 目录**：导入文件夹的代码已写，能否识别取决于设备与系统，未验证。
- 真机 HealthKit 中 `cyclingPower`、`cyclingCadence`、`cyclingSpeed`、`cyclingFunctionalThresholdPower` 的实际读取（标识符来自 SDK，数据是否存在未知）。
- 重签名后 App Group 与分享面板中“用元气打开”的 FIT 文件是否可用。
- 真机上的 FIT 导入（文件 App 与文件夹）与备份恢复中导入骑行的重新解析。
- 手表 App 与复杂功能：本轮只做构建验证（没有手表模拟器运行时，见 D-084）。

### 界面未做的部分（D-125，需要真机数据或后续轮次）
- 骑行详情的功率 / 心率双轴逐秒曲线与分圈表（只有导入的 FIT 才有逐秒数据，HealthKit 骑行的逐秒数据不进入汇总）。
- 心率区间分布。
- 浏览页的 EF 趋势（已放在 FTP 页）与 FTP 历史趋势（FTP 的历史值没有保存）。
- “数据来源识别”的手动优先级选择：只列出检测到的 Garmin 来源，优先级按 D-107 固定。
- 心肺适能页中的 EF 与 20 分钟功率趋势（PRD §5.12.2 的两项新增）。

### 给用户的使用建议
1. 如果心率带与功率计支持 ANT+ 和蓝牙同时连接，可以把它们也通过蓝牙配对到 Apple Watch（在手表的“设置 → 蓝牙”中）。这样在手表上开运动时，心率带的心率和功率计的功率会直接写入健康数据，不需要再导入 FIT。注意：部分功率计限制蓝牙连接数，可能需要先断开手机上的其他 App。
2. 没开手表运动的那一半骑行：导入 FIT 是最完整的方案。可以从 Garmin Connect 网页版的活动页面“导出原始文件”（得到包含 FIT 的 zip，解压后导入），或者从码表的 `Garmin/Activity` 目录拷出来。
3. 导入的 FIT 文件只保存在本机并包含在加密备份中，不会写回健康数据，因此换机或恢复时请先导出备份。
