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

## 阶段 3：基线、质量、恢复、睡眠、生病预警、流水线 —— 🚧 基本完成（1 项未通过，见备注）
- 提交：见 `git log --oneline`（提交信息 `feat(scoring): ...`）
- 测试：VigorScoring 79 个通过；VigorHealth 26 个通过、1 个未通过（分区分布，见下）
- 构建：iOS ✅（全 App）  watchOS —
- 备注：
  - 未通过项：“分区分布 15%–65%” 检验，红区 14.3%。断言未修改；决策见 DECISIONS D-038，需要用户决定。
  - 流水线性能：120 晚全量计算在测试中约 1 秒（调试构建、单独运行），断言 < 2 秒通过。
  - 生病预警的合成检验通过：倒数第 20、19 晚为“注意”→“可能不适”，两晚排除；饮酒夜不排除；混杂饮酒的生病夜只提示不排除。
  - 未覆盖：跨时区排除（D-029）与手动排除只有代码路径，没有专门的测试。
  - 未实现：RMSSD 展示的 SDNN 估算（D-036，阶段 6）。
  - 决策 D-021 至 D-038。
