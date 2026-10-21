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
