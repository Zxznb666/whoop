# 施工任务：元气 Vigor · M1–M5 补完

M1–M5 的第一轮施工完成了阶段 1–5，阶段 6、7、9 只完成一部分，阶段 8 没做。之后，同步链路和后台的阻断问题已经人工修好（提交 `f7d8d3b`，见 `docs/DECISIONS.md` D-068 至 D-070）。本轮把剩下的部分**一次性补完**。

---

## 0. 开工前必读

1. `docs/prompts/M1-M5-build-prompt.md`：其中 §1（环境）、§2（硬性规则）、§4（裁决）、§6（进度文件）、§7（验证命令）在本轮**全部继续有效**。
2. `docs/BUILD-PROGRESS.md`、`docs/BUILD-REPORT.md`、`docs/DECISIONS.md`（重点看 D-047、D-060、D-066、D-067、D-068 至 D-070）。
3. `docs/PRD.md` 仍是功能规格的来源。
4. **不要执行** `docs/prompts/M6-cycling-build-prompt.md`，那是下一轮的任务；也不要提交这个文件。
5. 本轮进度记在 `docs/BUILD-PROGRESS.md` 末尾新增的“补完 F1–F8”下；中断后从第一个未完成项继续。

## 1. 本轮不许改动的部分

同步链路是人工修复的，有对应的测试。除了 F7 明确要求的扩展，**不要重构**以下内容：
- `SyncEngine` 的刷新模式与快照缓存合并逻辑（`RefreshMode`、`readSnapshot`、`HealthSnapshot.merging`）
- `AppBootstrap.refreshNow` 的合并逻辑
- `BackgroundSync` 中观察者的完成回调时机，以及后台任务的提交

所有新功能的数据刷新都通过 `AppBootstrap.shared.refreshNow()` 触发，不能自己另起读取 HealthKit 的路径。

## 2. 任务清单（按顺序执行，每项都要：实现 → 测试 → 构建 → 提交 → 更新进度）

### F1 日志录入（真机使用的前提）
1. 日志页顶部新增“今天的日志”卡片，点进填写页：
   - 问题针对的是“昨天”，日期归属与 `JournalEntry.night` 的现有约定保持一致（先读代码确认，再写）。
   - 默认题目见 PRD §6.5；题型支持“是 / 否”和“数量”。
   - 自定义题目：在设置中增删、排序，保存在 UserDefaults。
   - 主观精力 1–5、“感觉不适”开关（它连接生病预警的确认，PRD §5.12.1）。
   - HealthKit 自动填充项（咖啡因、酒精、正念时长、日照、情绪）显示为只读的预填值，取自 `SyncEngine.cachedSnapshot()`。
   - 保存时调用 `ScoreRepository.saveJournal`，然后调用 `AppBootstrap.shared.refreshNow()`，让洞察和生病预警生效。
2. 已填写的日期可以再次编辑。
3. 醒来后的日志提醒通知：在恢复分数的通知之后发出；当天已填写则不发。
4. 测试：日志的保存与读取往返、同一天重复保存会覆盖、题目配置的编解码。

### F2 压力公式修正（施工文档 §4.7 原公式有错）
原公式用**夜间静息心率**作为基准。白天安静时的心率通常比睡眠时高 20%–40%，所以压力几乎总是满格（D-047：合成数据平均 2.96）。改为：
- **日间安静窗口**：醒着、没有训练、步数 < 100、至少 2 个心率点的 15 分钟窗口。
- **每天的日间安静心率** = 当天所有安静窗口平均心率的 P20。
- **基线 μ_day** = 之前 14 个周期“日间安静心率”的中位数（**不使用当天及以后的数据**）；不足 3 天时，用夜间静息心率 μ × 1.15 代替。
- `stress = clamp(((窗口平均心率 − μ_day) / μ_day) / 0.10, 0, 3)`；当日 z_hrv < −1 时再加 0.5（上限 3）。
- 测试：窗口心率 = μ_day → 0；= μ_day × 1.10 → 1.0；= μ_day × 1.35 → 3；不足 3 天时使用退回值；基线不包含当天。合成场景中，非训练周期的平均压力 < 1.5。
- 黄金快照会因此变化：用 `vigor-replay --update-golden` 更新，并在 DECISIONS 中写明原因。
- 非训练日负荷偏高（D-047，平均 11.6）**这一轮不改**，留给真实数据校准；只在 DECISIONS 中注明。

### F3 阶段 8：手表、小组件、复杂功能、WatchConnectivity
完整执行 `M1-M5-build-prompt.md` 阶段 8 的全部要求，另外注意：
- target 与 bundle 的名字必须和 `scripts/package-ipa.sh` 中的路径一致：`VigorWatch.app`（嵌在 `Vigor.app/Watch/` 中）、`VigorWidgets.appex`（嵌在 `Vigor.app/PlugIns/` 中）、`VigorWatchWidgets.appex`（嵌在 `VigorWatch.app/PlugIns/` 中）；entitlements 文件分别为 `Watch/VigorWatch.entitlements`、`Widgets/VigorWidgets.entitlements`、`WatchWidgets/VigorWatchWidgets.entitlements`。如果你确实需要改名，同步修改脚本。
- App Group 不可用是**预期中的情况**（重签名可能丢掉这个权限）：小组件读不到共享状态时，显示“打开元气以更新”；手表收不到数据时，显示上一次的缓存。任何一种情况都不能崩溃。
- 手机端在 `SyncEngine` 刷新成功后推送共享状态给手表：在 `AppBootstrap.perform` 成功之后调用，不要改 `SyncEngine` 的内部逻辑。
- 构建后检查 `build/ipa/.../Vigor.app` 的目录结构是否符合上面的路径。
- 验证：iOS 构建、watchOS 模拟器构建都要 0 个 error；有手表模拟器时截一张手表首页的图。

### F4 实验室升级与校准界面
按 PRD §6.11 与 `M1-M5-build-prompt.md` 阶段 6 第 3 条、阶段 9 第 3 条补齐：
- 任选一晚：HRV 段表（时间、分期、位置、有效拍数、剔除率、RMSSD、权重 q/p/s、是否采用、丢弃原因）、Poincaré 图（伪迹用不同颜色）、会话拼装信息。
- 基线曲线（μ ± σ 的历史曲线，标出冷启动收缩）、Shapley 明细、睡眠负债递推表、质量分各分量。
- 参数面板：编辑 `ScoringConfig` 中的关键参数 → 生成新的 configVersion → 全量重算 → 新旧版本对比（分数差异的分布与逐日列表）→ 采用或回滚。
- 消融对比：去掉任意一个分量后的恢复分布。
- 校准：岭回归权重拟合（样本不足 45 天时说明原因并禁用）、基础睡眠需求建议值，采用前要确认。
- 导出：CSV（每日汇总）、JSON（特征）、调试快照。

### F5 备份、Claude 教练、报告、亮点
- 备份：设置中的导出与导入界面（`fileExporter` / `fileImporter`），设置密码、确认密码，密码错误时给出清楚的提示；导入后触发全量重算。
- Claude 教练：设置中填写 API key（存钥匙串）、选择模型、测试连接；**每次发送前显示即将发送的 JSON 预览**，用户确认后才发送（PRD §9.3）。对话页可以用。
- 周报、月报：AI 总结（端侧 → Claude → 模板，依次降级）；每周日 20:00 发送周报通知。
- 亮点（Highlights）与教练一句话的模板版（D-067）：至少 8 条规则，覆盖 HRV 趋势、睡眠负债、负荷平衡、一致性、生病预警、校准期、数据质量低、未佩戴。
- 心肺适能在浏览页的入口与详情页。

### F6 小问题
- 温度偏差显示 `-0.0 °C`：格式化时把 −0.05 到 0.05 之间的值显示为 `0.0`，并检查其他会出现负零的格式化函数。
- 通过 `-VigorRoute` 打开标签页根页面时（睡眠、负荷、日志、浏览），不要压入导航栈，直接切换标签页；只有二级页面才压栈。
- 生病预警的“连续两晚”：前一个周期的醒来时间距离本周期超过 36 小时，就不算连续。补测试。

### F7 手动修正与排除的持久化
- 睡眠页“修正睡眠时段”（PRD §5.2 第 8 条）与设置中的“排除指定夜晚”：保存在 SwiftData 中。
- 扩展 `ScoringSettings`，加上 `sleepOverrides` 与 `manualExcludedNights`，在 `SyncEngine.refresh` 中传给 `PipelineInput`（这是 §1 唯一允许的同步链路改动）；`AppBootstrap.perform` 读取并传入。修改后触发 `refreshNow(mode: .window(days: 30))`。
- 测试：设置被正确传入流水线（用 `SyncEngineTests` 中的 `RecordingSource` 方式）。

### F8 截图检查、打包、报告
1. 运行 `scripts/screenshots.sh`，浅色与深色共 32 张以上（新增的页面也要加路由）。**逐张打开检查**：没有空白、截断、占位文字，深色模式下文字可读。在 `BUILD-REPORT.md` 中列出每张图的检查结论。
2. 版本号改为 `1.1.0`（build 4），运行 `scripts/package-ipa.sh`，确认输出 `dist/Vigor-1.1.0.ipa`。解包后检查手表 App 和两个小组件扩展都在，且各自带有 entitlements。
3. 更新 `docs/BUILD-REPORT.md`：本轮完成清单、测试数、截图结论、仍未验证的项（真机 HealthKit、后台、通知、手表训练模式、WatchConnectivity、小组件刷新、全能签重签名后的各项权限）。

## 3. 完成标准
- [ ] F1–F8 在 `BUILD-PROGRESS.md` 中全部为 ✅（⚠️ 要有原因）
- [ ] 全部包的测试通过（包括 `SyncEngineTests` 与 `SnapshotCacheTests`），黄金快照的变化已在 DECISIONS 中说明
- [ ] iOS 构建（含手表与小组件）和 watchOS 构建都是 0 个 error
- [ ] `dist/Vigor-1.1.0.ipa` 中包含手表 App 和两个小组件扩展
- [ ] 截图已逐张检查并记录结论
- [ ] 所有改动都已提交到本地 git（不包括 `docs/prompts/M6-cycling-build-prompt.md`）
