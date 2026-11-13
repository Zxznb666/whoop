# Muse 参考实现

无依赖的 JavaScript（ES 模块 + Node 自带测试运行器），实现 `Muse/ALGORITHM.md` 的 A / B / C 三档算法。用途：

1. 证明算法正确：和 Vigor 完整管线逐项对照（`COMPARISON.md`）。
2. 导出 golden：每天每个中间量的“标准答案”，用来核对 Muse 空间里的数字。
3. 驱动视觉样机：`Muse/mock/` 读的就是这里导出的 golden。

需要 Node ≥ 20（本机 v24.13.0）。不需要 `npm install`。

## 目录

| 路径 | 内容 |
|---|---|
| `src/config.js` | 全部常数及出处 |
| `src/sleep.js` | 睡眠会话、睡眠指标、SRI、需求与负债、睡眠分、分期图 |
| `src/baseline.js` | 稳健基线 |
| `src/recovery.js` | 恢复分数、扣分、Shapley、生病预警、负荷目标、ACWR |
| `src/load.js` | 分钟网格、TRIMP、Strain；B/C 档负荷估算 |
| `src/tiers.js` | 把完整快照降级成 A / B / C 档的输入 |
| `src/pipeline.js` | 逐晚评分流水线 |
| `test/` | 36 项测试：核心数学、9 条 noop 缺陷、合成数据整体对照与 golden 回归 |
| `scripts/compare.js` | 三档 vs Vigor 对照 → `golden/comparison.json`（`COMPARISON.md` 由它的输出整理） |
| `scripts/golden.js` | 导出 golden → `golden/<数据名>/{A,B,C}.json` 与 `*-days.csv` |
| `vigor-export/` | 小型 Swift 工具，只读调用 `Packages/VigorScoring`、`VigorHealth`，导出快照与 Vigor 结果 |
| `fixtures/synthetic-seed42/` | 合成快照（去掉逐拍序列，gzip）+ Vigor 结果 |

## 常用命令

```bash
cd Muse/reference && npm test
```

```bash
cd Muse/reference && node scripts/compare.js
```

```bash
cd Muse/reference && node scripts/golden.js
```

重新生成合成 fixture（一般不需要）：

```bash
cd Muse/reference/vigor-export && swift build -c release && ./.build/release/vigor-export --synthetic ../fixtures/synthetic-seed42 && gzip -kf -9 ../fixtures/synthetic-seed42/snapshot.json
```

## 用真实数据验证（需要你在 iPhone 上导出一次）

仓库里**没有**你的真实数据快照，以上结论都来自合成数据。步骤：

1. iPhone 上打开 Vigor → 摘要页右上角“实验室” → 往下到“导出”分区 → 点“生成导出文件（CSV · JSON · 调试快照）” → 分享 `vigor-debug-snapshot-<时间>.json`（隔空投送到这台 Mac，例如放到“下载”）。这个文件含全部健康原始数据，不要发给别人。
2. 在 Mac 上生成真实数据的 fixture（目录名以 `real-` 开头，已在 `.gitignore` 里，不会被提交）：

```bash
cd Muse/reference/vigor-export && swift build -c release && ./.build/release/vigor-export --snapshot ~/Downloads/vigor-debug-snapshot-XXXX.json ../fixtures/real-latest
```

3. 对照与 golden：

```bash
cd Muse/reference && node scripts/compare.js fixtures/real-latest && node scripts/golden.js fixtures/real-latest
```

真实 golden 在 `golden/real-latest/`，同样不提交。阶段 4 的验收提示词让 Muse 列出某天的中间量，就拿它和这里的 `A-days.csv` 对。

## 与 Vigor 的已知差异（都是有意的，见 ALGORITHM.md §8）

- HRV：SDNN 睡眠窗口中位数（Vigor：逐拍 RMSSD）。
- 夜间静息心率：样本池不含逐拍序列的平均心率。
- 15–60 分钟心率空窗：按静息处理，不做“活动能量 → 心率”回归。
- 心率来源去重：同一分钟所有来源取平均（Vigor 按来源优先级只取一个）。
- 没有日志：生病预警不考虑饮酒/桑拿等混杂因素；没有晨测。
- 时区固定 +08:00；不做跨时区旅行排除。
