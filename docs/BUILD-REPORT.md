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
