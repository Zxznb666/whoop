# 元气 Vigor · 施工进度（M1–M5）

> 施工文档：`docs/prompts/M1-M5-build-prompt.md`；规格：`docs/PRD.md` v0.2；裁决：施工文档 §4 与 `docs/DECISIONS.md`。

## 阶段 1：数据层升级 —— ✅ 完成
- 提交：见 `git log --oneline`（提交信息 `feat(data): ...`）
- 测试：VigorScoring 23 个通过，VigorHealth 19 个通过（含 v1→v2 解码、v2 往返、合成场景确定性与注入事件、心跳缓存编解码与存取）
- 构建：iOS ✅（全 App，含两个包）  watchOS —（阶段 8 再做）
- 备注：
  - 快照 v2 + v1 升级；合成场景 v2；心跳缓存；增量读取 `HealthSyncReader`（actor）。
  - 实时数据源（`LiveHealthDataSource`）的 HealthKit 读取只能编译验证，真机未验证。
  - HealthKit SDK 无创建时间，`creationDate` 留空（见 DECISIONS D-004）。
  - 决策见 `docs/DECISIONS.md` D-001 至 D-009。

## 阶段 2：夜间算法 v2 —— ✅ 完成
- 提交：见 `git log --oneline`（提交信息 `feat(scoring): ...`）
- 测试：VigorScoring 40 个通过（含施工文档阶段 2 表格的全部 14 行），VigorHealth 19 个通过
- 构建：iOS ✅（全 App）  watchOS —
- 备注：
  - `HRVConfig` → `ScoringConfig`；`SegmentResult` → `HRVWindow`；`NightReport` → `NightFeatures`。
  - 实验室页的质量标识暂时移除（D-017），阶段 3 恢复。
  - 决策 D-010 至 D-020。

## 阶段 3：基线、质量、恢复、睡眠、生病预警、流水线 —— ✅ 完成
- 提交：见 `git log --oneline`（提交信息 `feat(scoring): ...`）
- 测试：VigorScoring 79 个通过；VigorHealth 26 个通过
- 构建：iOS ✅（全 App）  watchOS —
- 备注：
  - 分区分布检验：阶段 3 时红区 14.3% 未通过；阶段 4 加入负荷后（睡眠需求的负荷追加改变了睡眠分）为红 18.5%，通过。见 D-038，不是调参的结果。
  - 流水线性能：120 晚全量计算在测试中约 1 秒（调试构建、单独运行），断言 < 2 秒通过。
  - 生病预警的合成检验通过：倒数第 20、19 晚为“注意”→“可能不适”，两晚排除；饮酒夜不排除；混杂饮酒的生病夜只提示不排除。
  - 未覆盖：跨时区排除（D-029）与手动排除只有代码路径，没有专门的测试。
  - 未实现：RMSSD 展示的 SDNN 估算（D-036，阶段 6）。
  - 决策 D-021 至 D-038。

## 阶段 4：负荷 —— ✅ 完成
- 提交：见 `git log --oneline`（提交信息 `feat(load): ...`）
- 测试：VigorScoring 89 个通过（含施工文档阶段 4 表格的全部 6 行与压力规则）；VigorHealth 28 个通过（含训练周期负荷高于非训练周期）
- 构建：iOS ✅  watchOS —
- 备注：
  - 周期 = 醒来 → 下一次主睡眠入睡；睡眠需求的负荷追加使用上一周期的 Strain（替代阶段 3 的按日输入）。
  - 分钟时间线、活动能量回归（前缀和）、最大心率的自动上调、压力、ACWR 与目标区间均已接入流水线。
  - 合成数据的负荷与压力偏高（D-047），需要真实数据校准。
  - 决策 D-039 至 D-047；D-038 的状态已更新。

## 阶段 5：持久化、同步引擎、后台、通知、回放工具、黄金快照 —— ✅ 完成（部分项见备注）
- 提交：见 `git log --oneline`（提交信息 `feat(store): ...` 等）
- 测试：VigorStore 4 个通过（SwiftData 内存容器）；VigorEngine 4 个通过（通知规则）；`Tools/VigorReplay` 4 个通过（黄金快照、差异报告、CSV 行数、参数解析）；VigorScoring 89、VigorHealth 28（均已通过）
- 构建：iOS ✅（全 App，含 VigorStore、VigorEngine、后台与通知代码）  watchOS —
- 备注：
  - `vigor-replay` 已实际运行：`--synthetic --update-golden` 生成了 `Tools/VigorReplay/Tests/VigorReplayCoreTests/Resources/golden-synthetic-seed42.csv`（120 行）；输出 `nights.csv`、`cycles.csv`、`baselines.csv` 行数正确（119 个周期 + 表头）。
  - 同步路径未接入锚点增量读取（D-048）；通知类型未全部实现（D-053）。
  - 后台任务、HealthKit 观察者、通知的真机行为均未验证。
  - 决策 D-048 至 D-054。

## 阶段 6：设计系统 + 主界面 —— 🚧 部分完成
- 提交：`0e2b628`（UI）；`Packages/VigorDesign` 的提交见 `git log`
- 测试：VigorDesign 2 个通过；其余包未变化（VigorScoring 89、VigorHealth 28、VigorStore 4、VigorEngine 4、VigorReplay 4）
- 构建：iOS ✅  watchOS —
- 已完成：`VigorDesign`（令牌与 ScoreRing、MetricCard、RangeChart、ContributionWaterfall、Hypnogram、HRTimeline、QualityBadge、StateBanner、SectionCard，各有 `#Preview`）；五个标签页（摘要、睡眠、负荷、日志、浏览）；恢复、睡眠、负荷、训练列表、指标详情、浏览、设置、诊断、欢迎页；路由表与 `-VigorRoute`；`scripts/screenshots.sh`（16 个路由 × 浅色/深色，共 32 张）。
- 未完成：
  - 实验室升级（HRV 段表、基线曲线、Shapley 与负债递推、参数面板、全量重算与版本对比、消融）。目前 `lab` 与 `lab:night` 仍是 M0 的实验室页。
  - 截图人工检查：只检查了摘要、恢复、睡眠、负荷四张。其余 28 张未逐张检查。
  - 日志页、报告页、教练页仍是占位。
- 备注：`Info.plist` 由 XcodeGen 从 `project.yml` 生成，后台相关键已移入 `project.yml`（见提交 `0e2b628`）。

## 阶段 7：日志、洞察、身体年龄、心肺适能、报告 —— 🚧 部分完成
- 提交：见 `git log --oneline`（提交信息 `feat(insights): ...`）
- 测试：VigorScoring 102 个通过（含 Welch 的 t 分布锚点 p ≈ 0.07339、Spearman、饮酒洞察的文案、周报边界、身体年龄锚点与截断、心肺适能斜率）；VigorHealth 29 个通过（含“饮酒排第一”）；VigorReplay 4 个通过（黄金快照不变）
- 构建：iOS ✅
- 已完成：Welch 检验、Spearman、t 分布；影响洞察（按效应量排序，每组至少 5 个样本）；周报与月报的纯函数；身体年龄与心肺适能趋势；日志页显示洞察，报告页显示周报，浏览页显示身体年龄。
- 未完成：日志问卷的填写界面与醒来后的提醒；亮点与教练模板；心肺适能的界面入口；报告推送。见 D-060。
- 备注：洞察在合成数据上排第一的是“饮酒”（测试断言）。

## 阶段 8：手表 App、小组件、App Intents —— ❌ 未完成（见 D-066）
- 已完成：App Intents（今天恢复怎么样、今天负荷多少、今晚几点睡），位于主 App 中（D-064）。
- 未完成：watchOS App、训练模式、复杂功能、iOS 小组件、WatchConnectivity、App Group 配置。没有 watchOS 模拟器运行时，手表部分只能做构建验证，而这一步还没有做。

## 阶段 9：AI 教练、备份、校准、诊断、打包、报告 —— 🚧 部分完成
- 测试：VigorCoach 6 个通过（路由、模板、确认门控、Claude 请求头与模型、响应解析、预览一致）；VigorStore 9 个通过（含备份往返、错误密码、篡改检测、PBKDF2）；VigorScoring 106 个通过（含岭回归、Cholesky、校准切分与门控）。
- 已完成：
  - 打包：`dist/Vigor-1.0.0.ipa`（ad-hoc 签名，含 HealthKit 权限，版本 1.0.0）。
  - 诊断页（显示 Bundle ID、版本、App Group 可用性、错误日志原文）。
  - 备份的加密与解密（界面未接入）。
  - 校准的算法（界面未接入）。
  - 教练：模板与端侧适配，界面显示“今日一句”。
- 未完成：Claude 教练的 key 录入与确认弹窗；周报与月报的 AI 总结；备份的导入导出界面；实验室中的校准界面与回滚；决策摘要见 `docs/DECISIONS.md`（D-001 至 D-067）；施工报告见 `docs/BUILD-REPORT.md`，其中的“摘要”部分仍需补充。
- 详见 `docs/BUILD-REPORT.md`。

## 补完 F1–F8（施工文档 M5-completion-build-prompt.md）

### F1 日志录入 —— ✅ 完成
- 提交：见 `git log --oneline`（提交信息 `feat(journal): ...`）
- 测试：VigorScoring 111 个通过（新增 5 个：题目编解码、旧记录解码、自动填充）；VigorStore 12 个通过（新增 3 个：往返、同日覆盖、区间查询）；VigorEngine 13 个通过（新增 5 个：日志提醒）
- 构建：iOS ✅  watchOS —
- 备注：日志页顶部“今天的日志”卡片；题目设置在日志页右上角与设置页；决策 D-071 至 D-074。真机上的提醒投递未验证。

### F2 压力公式修正 —— ✅ 完成
- 提交：见 `git log --oneline`（提交信息 `fix(scoring): ...`）
- 测试：VigorScoring 118 个通过（新增 7 个：锚点 0/1/3、P20、回退、中位数、最近 14 周期、饱和回归、z_hrv 修正）；VigorHealth 34 个通过（新增 2 个：非训练周期平均压力 < 1.5、不用未来数据）；VigorReplay 4 个通过（黄金快照未变，见 D-077）
- 构建：iOS —（F2 仅改动评分包，随 F1 的 App 构建一并验证；F3 后重新构建）
- 备注：决策 D-075 至 D-077。非训练日负荷偏高（D-047）按施工文档保留，未改。

### F3 手表、小组件、WatchConnectivity —— ✅ 完成（运行未验证，见 D-084）
- 提交：见 `git log --oneline`（提交信息 `feat(watch): ...`）
- 测试：VigorStore 15 个通过（新增 3 个：共享状态往返、旧载荷解码、约定的键与 App Group 标识）；其他包不变
- 构建：iOS ✅（含手表与两个小组件，`Vigor.app/Watch/VigorWatch.app`、`Vigor.app/PlugIns/VigorWidgets.appex`、`VigorWatch.app/PlugIns/VigorWatchWidgets.appex` 已确认）  watchOS ✅（`VigorWatch` scheme，generic watchOS Simulator）
- 备注：手表模拟器运行时不可用（D-084），训练模式与小组件的真实刷新只能在真机上验证。App Intents 读取顺序已修正（D-081）。

### F4 实验室升级与校准界面 —— ✅ 完成（权重采用见 D-088）
- 提交：见 `git log --oneline`（提交信息 `feat(lab): ...`）
- 测试：VigorHealth 40 个通过（新增 6 个：版本对比、消融、消融基准与评分器一致、校准样本、CSV/JSON 导出）；VigorStore 16 个通过（新增 1 个：配置版本历史）
- 构建：iOS ✅  watchOS —（F4 不改手表代码）
- 备注：新增 `LabAnalysis`、`DailyExport`（VigorScoring），`PipelineLabModel` 与 `PipelineLabSections`（App）。截图检查见 F8。

### F5 备份、Claude 教练、报告、亮点 —— ✅ 完成（端侧路径未在模拟器验证，见 D-092）
- 提交：见 `git log --oneline`（提交信息 `feat(coach): ...`）
- 测试：VigorCoach 11 个通过（新增 5 个：来源顺序、模板周报 / 月报、Claude 文本请求与解析、周报预览）；VigorHealth 46 个通过（新增 6 个：亮点目录、合成覆盖、生病提示、校准期、数据质量与佩戴的副本验证）；VigorEngine 15 个通过（新增 2 个：周报推送）
- 构建：iOS ✅
- 备注：备份与恢复页、教练设置页（Keychain）、周报 AI 总结卡片、心肺适能详情、亮点卡片、周报推送。备份中的手动修正在 F7 接入后补全（D-094）。

### F6 小问题 —— ✅ 完成
- 提交：见 `git log --oneline`（提交信息 `fix(ui): ...`）
- 测试：VigorScoring 120 个通过（新增 2 个：显示负零、连续两晚的 36 小时边界）；VigorHealth 46 个通过；VigorReplay 4 个通过（黄金快照不变）
- 构建：iOS ✅
- 备注：决策 D-096 至 D-098。`-VigorRoute` 的标签页根页面不压栈；截图检查见 F8。

### F7 手动修正与排除的持久化 —— ✅ 完成
- 提交：见 `git log --oneline`（提交信息 `feat(corrections): ...`）
- 测试：VigorStore 20 个通过（新增 4 个：睡眠修正往返、排除往返、日期键解析、备份键一致）；VigorEngine 17 个通过（新增 2 个：修正与排除经同步链路到达流水线；默认设置不排除）
- 构建：iOS ✅
- 备注：睡眠页的“修正睡眠时段”、设置中的“排除指定夜晚”、备份中的修正。决策 D-099 至 D-102。

### F8 截图检查、打包、报告 —— ✅ 完成（部分截图未逐张检查，见 BUILD-REPORT）
- 提交：见 `git log --oneline`（提交信息 `docs(report): ...`）
- 测试：全部包通过，合计 220 个（VigorScoring 120、VigorHealth 46、VigorStore 20、VigorEngine 17、VigorCoach 11、VigorDesign 2、VigorReplay 4）
- 构建：iOS ✅  watchOS ✅（`VigorWatch` scheme，generic watchOS Simulator）
- 截图：`scripts/screenshots.sh`，22 个路由 × 浅色 / 深色 = 44 张，全部已生成；逐张检查 25 张（结论见 BUILD-REPORT.md），其余 19 张未逐张检查
- IPA：`dist/Vigor-1.1.0.ipa`（版本 1.1.0 build 4），内含 `Payload/Vigor.app`（com.example.vigor）、`Watch/VigorWatch.app`（com.example.vigor.watchkitapp）、`PlugIns/VigorWidgets.appex`（com.example.vigor.widgets）、`Watch/VigorWatch.app/PlugIns/VigorWatchWidgets.appex`（com.example.vigor.watchkitapp.widgets）；四个 bundle 均为 ad-hoc 签名，entitlements 已逐个核对

## 阶段 10：VigorFIT 解析器与测试编码器 —— ✅ 完成
- 提交：见 `git log --oneline`（提交信息 `feat(fit): ...`）
- 测试：VigorFIT 14 个通过（CRC 检查值、全部 16 种编码选项组合往返、压缩头确实生效、无效值为 nil、改字节报 CRC 错误、头 CRC、签名、截断、逐秒数组对齐、暂停区间、开放暂停、去重标识；真实文件测试在无 `.fit` 时跳过）
- 构建：不适用（纯 Foundation 包，随 iOS 构建验证）
- 备注：解析器与编码器按 FIT SDK 规则手写；编码器只在测试 target 中，`Tests/Fixtures/real/` 放入真实 `.fit` 文件后会自动运行解析测试。

## 阶段 11：快照 v3、骑行分组、去重、指标、流水线 —— ✅ 完成
- 提交：见 `git log --oneline`（提交信息 `feat(cycling): ...`）
- 测试：VigorScoring 146 个通过（新增：骑行数学 11、分钟去重 5、骑行分析 10 等）；VigorHealth 52 个通过（新增：合成骑行 5、快照 v2/v3 与合并 2 等）；VigorReplay 4 个通过（黄金快照已按 D-117 更新）；VigorStore 20、VigorEngine 17、VigorCoach 11、VigorDesign 2 个通过（不变）
- 构建：iOS ✅（`xcodebuild` 生成项目后 0 个 error）  watchOS 未在本阶段重新构建（阶段 13 统一做）
- 备注：决策 D-103 至 D-118。流水线耗时见 D-116（调试构建 1.8 秒，断言 < 2 秒，余量很小）。骑行的 FTP 手动设置目前只能通过流水线输入，界面在阶段 12 接入。导入的骑行目前不会被同步层自动填入快照，阶段 12 接入导入流程时补上。

## 阶段 12：导入、备份与骑行界面 —— ✅ 完成（真机验证待做，见 BUILD-REPORT）
- 提交：见 `git log --oneline`（提交信息 `feat(cycling-ui): ...`）
- 测试：VigorScoring 151 个通过（新增：稀疏功率不是 0 W、覆盖不足 50% 不出 NP、窗口前的样本不写入骑行、只有 Garmin 训练时 Garmin 心率优先于手表被动心率）；VigorHealth 52 个通过；VigorFIT 14 个通过；VigorStore 26 个通过（新增：导入去重、删除、原始文件往返、无效文件拒绝、骑行汇总往返、备份中的导入骑行往返与 v1 兼容）；VigorEngine 17、VigorCoach 11、VigorDesign 2 个通过；VigorReplay 4 个通过（黄金快照已更新，见 D-132）。合计 277 个。
- 构建：iOS ✅（`Vigor` scheme，0 个 error）  watchOS ✅（`VigorWatch` scheme，0 个 error）
- 截图：`ride`、`ride:garminOnly`、`pmc`、`metric:ftp` 共 8 张，已逐张检查（结论见 BUILD-REPORT 的 M6 一节）。`pmc` 与 `metric:ftp` 在 iPhone 17 Pro Max 上重拍（同一台 iPhone 17 Pro 模拟器被另一个会话占用，见 BUILD-REPORT）；其余 `ride` 系列在 iPhone 17 Pro 上拍摄。
- 备注：决策 D-119 至 D-133。审查修正（D-128 至 D-133）：稀疏功率、覆盖率门槛、手表被动心率分类、中文日期。界面未做的项见 D-125。

## 阶段 13：打包 1.2.0、构建报告 —— ✅ 完成
- 提交：见 `git log --oneline`（提交信息 `docs(report): ...`）
- 测试：全部包合计 277 个通过（同阶段 12）
- 构建：iOS ✅  watchOS ✅
- IPA：`dist/Vigor-1.2.0.ipa`（版本 1.2.0，build 5；主 App、手表 App 与两个小组件均已核对）
- 备注：`docs/BUILD-REPORT.md` 的 M6 一节包含完成情况、截图逐张检查结论、未验证项与给用户的建议。

## M6 补完 C1–C6（施工文档 M6-completion-build-prompt.md）

### C1 骑行时间线数据 —— ✅ 完成
- 提交：见 `git log --oneline`（提交信息 `feat(cycling): ride timeline ...`）
- 测试：VigorScoring 158 个通过（新增 7 个：RideTimelineTests）；全部包合计 284 个通过
- 构建：iOS ✅  watchOS —（C1 不改界面）
- 备注：`RideTimelineBuilder` 放在 `Cycling/RideTimeline.swift`。分圈序号从 1 开始。FIT 路径用逐秒数组；非 FIT 的心率按分钟网格去重（D-130），空档以分钟为单位；HealthKit 功率的空档不超过 5 秒沿用前值，更长为 nil。`FITLap` 增加显式初始化器以便测试构造（VigorFIT）。

### C3 每次骑行的心率区间 —— ✅ 完成
- 提交：见 `git log --oneline`（提交信息 `feat(cycling): heart rate zones per ride`）
- 测试：VigorScoring 161 个通过（新增 3 个：CyclingZoneTests，含旧 JSON 解码为 nil 与往返）
- 构建：iOS ✅（见 C2 的构建记录）  watchOS —
- 备注：先于 C2 完成，因为 C2 的心率区间卡片读取这里的数据。口径为 PRD §5.1 的 HRR%（Z1 50–60 … Z5 90–100）；FIT 按秒、其他按分钟（每分钟 60 秒）。
