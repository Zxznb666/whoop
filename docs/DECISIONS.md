# 施工决策记录（M1–M5）

> 格式：编号 · 阶段 · 内容 · 原因。施工文档 §2.5 要求所有偏离、裁决、取舍都记录在此。PRD 本身不修改。

| 编号 | 阶段 | 内容 | 原因 |
|---|---|---|---|
| D-001 | 1 | `SleepStageSample` 存储 `productType` 等来源字段；`sourceIsWatch` 改为由 `productType` 推导的计算属性。保留 M0 形式的 `init(…sourceIsWatch:)` 作为便利构造器。 | 施工文档 §5 阶段 1 第 1 条要求删除或改为计算属性；保留便利构造器可让 M0 测试与生成器继续编译。 |
| D-002 | 1 | v1 快照通过独立的 `LegacySnapshotV1` 解码并升级：`sourceIsWatch` 映射为 `productType`（`Watch7,1` / `iPhone15,2`），v2 新增数组填空。`HealthSnapshot` 的 v2 新增字段用 `decodeIfPresent` 解码。 | 施工文档 §5 阶段 1 第 1 条：解码时能读取 v1，缺失字段填空数组。 |
| D-003 | 1 | M0 测试 “schemaVersion 不为 1 时抛出” 改为 “既不是 1 也不是 2 时抛出”，并用版本 3 验证报错；新增 v1 夹具解码测试。 | v2 已是受支持版本，旧断言的前提不再成立。断言没有放宽：不受支持的版本仍然报错。 |
| D-004 | 1 | HealthKit SDK 没有在 `HKSample` 上暴露创建时间（`creationDate`）。实时读取时该字段留空。 | 在本机 Xcode 27.1 的 SDK 接口中检索不到对应属性。影响：§5.2 步骤 2（同源重叠保留“创建时间较晚”的样本）无法直接实现，阶段 2 改为按 `endDate` 较晚者保留，并在阶段 2 的记录中注明。 |
| D-005 | 1 | `HealthSyncReader` 定义为 `actor`，而不是 `struct`。 | `UserDefaults` 在该 SDK 中不是 `Sendable`，不能放进 `Sendable` 的结构体；actor 不需要 `@unchecked`。 |
| D-006 | 1 | 心跳缓存：每条序列一个 `.hbc` 文件，二进制布局为 start/end（Float64）+ 拍数（UInt32）+ 每拍 t（Float64）与间隙标记（UInt8）。由 `HeartbeatCache` actor 管理，文件位于 `Application Support/HeartbeatCache/`。 | 施工文档 §4.3 的布局要求。 |
| D-007 | 1 | 合成场景 v2 的默认夜数为 120（M0 的 `SyntheticSnapshot.make` 默认仍为 30，保持兼容）。夜间心率的截断范围由 48–62 放宽为 46–70，以容纳生病夜与晚餐过晚夜的抬升。 | 施工文档 §4.8 要求新规则；生病 +6 bpm 与晚餐过晚的抬升会超过原截断。 |
| D-008 | 1 | 合成场景的注入事件清单 `SyntheticTruth` 使用醒来日的本地零点作为键；测试中“同一天”的判断使用 `Calendar.isDate(_:inSameDayAs:)`，不使用时间差阈值。 | 时间差阈值会把相邻夜晚的样本也匹配进来（测试开发中发现并修正）。 |
| D-009 | 1 | `SplitMix64` 移到独立文件 `SplitMix64.swift`，内容不变。 | 合成场景文件变大，分开便于阅读。随机数序列与 M0 完全一致。 |
