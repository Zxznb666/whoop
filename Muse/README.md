# Muse · WHOOP 风格恢复面板

在 Meta Muse 的“空间”里，用对话搭一个 Recovery / Strain / Sleep 面板，数据只来自 Apple Watch Series 10 → Apple Health。本目录不改 Vigor App 本身。

| 路径 | 内容 | 状态 |
|---|---|---|
| `prompts/00-probe.md` | 阶段 0：探测 Muse 读 Apple Health 的粒度、确定性、绘图、长度上限 | P1–P9 已完成（结论在文末）；P10 待做 |
| `ALGORITHM.md` | 分档算法规格：**H 每小时汇总 + 整晚睡眠会话（Muse 实测，§6A）**，以及 A / B / C 对照档；noop 九个缺陷与对策 | 完成 |
| `reference/` | Node 参考实现（零依赖）、测试、Vigor 对拍、golden 数据 | `npm test` 45/45 通过 |
| `DESIGN.md`、`mock/index.html` | WHOOP 风格视觉规格与单文件样机（默认 H 档） | 完成 |
| `prompts/01–08` | 阶段 4 构建提示词（H 档定稿），按编号依次粘贴到 Muse | **请按下面的顺序使用** |

## 构建顺序

1. `01-data-layer.md`：先填出生年、性别、验收日，粘贴；把 Muse 列出的那一行和小时值贴回核对。
2. `02-baseline.md` → `03-strain.md` → `04-sleep.md` → `05-recovery.md`：每条做完都贴回 `{验收日}` 的结果核对，对了再发下一条（负荷在睡眠之前，因为睡眠需求要用前一天的负荷；睡眠在恢复之前，因为恢复要用睡眠分）。
3. `06-pages.md`：四条页面提示词，一次一条，每条截图对照样机。
4. `07-check-and-fix.md`：全部做完后的验收；数字或样子不对时用里面的修正提示词。
5. `08-settings.md`：固定到主页、自动刷新、早晨提醒（等 P10 结果再调）。

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
