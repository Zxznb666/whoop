# Muse · WHOOP 风格恢复面板

在 Meta Muse 的“空间”里，用对话搭一个 Recovery / Strain / Sleep 面板，数据只来自 Apple Watch Series 10 → Apple Health。本目录不改 Vigor App 本身。

| 路径 | 内容 | 状态 |
|---|---|---|
| `prompts/00-probe.md` | 阶段 0：探测 Muse 读 Apple Health 的粒度、确定性、绘图、长度上限 | **请在 Muse 里运行，把结果贴回** |
| `ALGORITHM.md` | 分档（A 逐条样本 / B 分期睡眠 + 每日值 / C 只有每日汇总）算法规格，noop 九个缺陷与对策 | 完成 |
| `reference/` | Node 参考实现（零依赖）、测试、Vigor 对拍、golden 数据 | `npm test` 36/36 通过 |
| `DESIGN.md`、`mock/index.html` | WHOOP 风格视觉规格与单文件样机 | 完成 |
| `prompts/drafts/` | 阶段 4 构建提示词草稿（A/B/C） | **待探测结果确认** |

## 常用命令

```bash
cd Muse/reference && npm test
node scripts/compare.js            # 与 Vigor 全量结果对比
node scripts/golden.js             # 重新生成 golden
node scripts/build-mock.js         # 重新生成样机
```

真实数据：在 Vigor「实验室 → 导出」生成调试快照，然后见 `reference/README.md`。`real-*` 目录已被 `.gitignore` 排除，健康数据不入库。

## 参考来源

- **noop**（https://github.com/Zxznb666/noop_old），PolyForm Noncommercial 1.0.0 许可。本目录只参考其结构与页面组织，并分析了它的算法缺陷（见 `ALGORITHM.md` §2）；**没有复制它的任何代码**。`reference/test/helpers/noop-like.js` 是依据阅读结果自行重写的行为描述，仅用于缺陷对照测试。
- **元气 Vigor**（本仓库 `Packages/VigorScoring`、`Packages/VigorHealth`）：算法设计来源；`reference/vigor-export` 以只读方式调用它生成对照数据。
- **WHOOP Brand & Design Guidelines**（developer.whoop.com 公开 PDF）：配色核对。不使用 WHOOP 商标、Logo 或图形资产。
