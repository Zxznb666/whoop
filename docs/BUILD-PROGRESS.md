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
