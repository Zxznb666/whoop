// 施工文档 §3 的 9 条 noop 缺陷：每条构造能触发它的输入，断言我们的实现给出合理结果，
// 并在注释与断言里写明 noop 的做法在同样输入下会得到什么（noop 的做法见 helpers/noop-like.js 的复述）。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runStaged } from '../src/pipeline.js';
import { cycleLoadA, buildMinuteGrid, trimpPerMinute, hrr, strainFromTrimp } from '../src/load.js';
import { recoveryScore } from '../src/recovery.js';
import { baselineStat } from '../src/baseline.js';
import { buildSessions, sleepMetrics, hypnogram } from '../src/sleep.js';
import { startOfDayKey } from '../src/time.js';
import { at, night, hrSeries, scenario, addDays, STD_NIGHT, H, M } from './helpers/build.js';
import { dailyAverageSDNN, binnedMinRestingHR, firstGapTRIMP, strain100 } from './helpers/noop-like.js';

const dayOf = (days, k) => days.find((d) => d.wakeDay === k);

test('缺陷 1：HRV 只取睡眠窗口内的 SDNN，白天读数不影响恢复', () => {
  const base = scenario('2026-10-01', 12, (i) => (i === 11 ? { sdnn: [55, 60, 65], daytimeSDNN: [20, 22, 25] } : {}));
  const alt = scenario('2026-10-01', 12, (i) => (i === 11 ? { sdnn: [55, 60, 65], daytimeSDNN: [45, 48, 50] } : {}));
  const k = '2026-10-13';
  const a = dayOf(runStaged(base), k);
  const b = dayOf(runStaged(alt), k);
  assert.equal(a.recovery.inputs.hrvMs, 60, '睡眠窗口内 [55, 60, 65] 的中位数');
  assert.equal(a.recovery.score, b.recovery.score, '换掉白天的 SDNN，分数不变');
  // noop：自然日内全部 SDNN 的平均 → (55+60+65+20+22+25)/6 = 41.2 ms，白天读数把 HRV 拉低了 31%
  const noop = dailyAverageSDNN(base.sdnn, startOfDayKey(k));
  assert.ok(Math.abs(noop - 41.17) < 0.01);
  assert.notEqual(noop, dailyAverageSDNN(alt.sdnn, startOfDayKey(k)), 'noop 的 HRV 随白天读数变化');
});

test('缺陷 2：呼吸率、手腕温度、血氧都参与恢复（noop 手表路径只用 HRV + 静息心率）', () => {
  const normal = scenario('2026-10-01', 12);
  const sick = scenario('2026-10-01', 12, (i) => (i === 11 ? { resp: 18, temp: 37.0, spo2: 0.92 } : {}));
  const k = '2026-10-13';
  const n = dayOf(runStaged(normal), k).recovery;
  const s = dayOf(runStaged(sick), k).recovery;
  assert.ok(s.penalties.resp > 0 && s.penalties.temp > 0 && s.penalties.spo2 > 0, JSON.stringify(s.penalties));
  assert.ok(n.score - s.score > 15, `体征异常时恢复应明显下降：${n.score} → ${s.score}`);
  // noop：只看 HRV 和静息心率，两晚 z 值相同 → 分数相同，体征异常完全看不出来
  const noopN = recoveryScore({ zHRV: n.z.hrv, zRHR: n.z.rhr }).score;
  const noopS = recoveryScore({ zHRV: s.z.hrv, zRHR: s.z.rhr }).score;
  assert.equal(noopN, noopS);
});

test('缺陷 3：稀疏夜间心率下，静息心率用第 10 百分位，不被单个低值伪迹带偏', () => {
  const bed = at('2026-10-01', 23);
  const stages = night(bed, STD_NIGHT);
  const pts = hrSeries(bed, bed + 8 * H, 300, (t) => 52 + ((t / 300) % 3) - 1); // 51–53，每 5 分钟一个点
  pts.push({ date: bed + 4 * H + 30, bpm: 38 }); // 一个伪迹低点
  const input = { tier: 'A', profile: { birthYear: 1994, sex: 'male' }, rangeStart: bed - H, asOf: bed + 10 * H,
    sleep: stages, inBed: [], heartRate: pts.sort((a, b) => a.date - b.date), sdnn: [{ start: bed + 3 * H, end: bed + 3 * H + 60, value: 50 }],
    restingHR: [], respiratory: [], wristTemperature: [], oxygen: [], breathing: [], workouts: [] };
  const d = runStaged(input).find((x) => x.recovery.status !== 'unworn');
  assert.equal(d.recovery.inputs.rhrSource, 'nightP10');
  assert.ok(d.recovery.inputs.rhr >= 50.9 && d.recovery.inputs.rhr <= 51.1, `p10 = ${d.recovery.inputs.rhr}`);
  // noop：每个 5 分钟箱只有 1–2 个点，没有箱子达到 5 个样本 → 退回所有箱均值的最小值 → 取到伪迹附近的值
  assert.ok(binnedMinRestingHR(pts, bed, bed + 8 * H) <= 45, 'noop 被伪迹带到 45 bpm 以下');
});

test('缺陷 4：心率间隔不均匀时按真实间隔积分（noop 用前两个样本的间隔乘以样本数）', () => {
  const rest = 55; const max = 185.6; const day0 = at('2026-10-02', 7);
  const f = (bpm) => trimpPerMinute(hrr(bpm, rest, max), 'male');
  // 情形 a：白天每 10 分钟一个点（70 bpm），傍晚 1 小时训练每 5 秒一个点（150 bpm）
  const a = [...hrSeries(day0, day0 + 11 * H, 600, 70), ...hrSeries(day0 + 11 * H, day0 + 12 * H, 5, 150)];
  const grid = buildMinuteGrid(a, day0, day0 + 13 * H);
  const ours = cycleLoadA({ grid, wake: day0, until: day0 + 13 * H, workouts: [], rest, max, sex: 'male' }, undefined);
  // 训练 60 分钟；70 bpm 的 HRR < 0.25 不计；训练前最后一个白天点（10:50）到训练开始相隔 10 分钟 ≤ 15，按线性插值爬升
  let expect = 60 * f(150);
  for (let i = 1; i < 10; i++) expect += f(70 + 8 * i);
  assert.ok(Math.abs(ours.trimp - expect) / expect < 0.01, `ours ${ours.trimp} vs ${expect}`);
  // noop：前两个点相隔 10 分钟 → 训练的 720 个点每个都算 10 分钟 → 约 120 倍高估
  assert.ok(firstGapTRIMP(a, f) / ours.trimp > 100);
  // 情形 b：开始时两个点相隔 5 秒，之后快走 3 小时每 10 分钟一个点（110 bpm）
  const b = [{ date: day0, bpm: 110 }, ...hrSeries(day0 + 5, day0 + 3 * H, 600, 110)];
  const gb = buildMinuteGrid(b, day0, day0 + 4 * H);
  const ob = cycleLoadA({ grid: gb, wake: day0, until: day0 + 4 * H, workouts: [], rest, max, sex: 'male' });
  assert.ok(Math.abs(ob.trimp - 170 * f(110)) / (170 * f(110)) < 0.08, `ours ${ob.trimp}`);
  // noop：每个点只算 5 秒 → 约 120 倍低估
  assert.ok(ob.trimp / firstGapTRIMP(b, f) > 50);
});

test('缺陷 5：负荷量程 0–21（WHOOP），不是 0–100', () => {
  for (const t of [0, 20, 87, 300, 600, 10000]) assert.ok(strainFromTrimp(t) <= 21);
  assert.ok(Math.abs(strainFromTrimp(87) - 12) < 0.05);
  // noop：100 × ln(88)/ln(7201) ≈ 50.4，“中等训练”显示成 50，和 WHOOP 的 12 不是一个量程
  assert.ok(Math.abs(strain100(87) - 50.4) < 0.1);
});

test('缺陷 6：一天 = 入睡到下次入睡；跨零点的睡眠和凌晨活动归属正确', () => {
  // 10/01 23:00 → 10/02 07:00 正常睡；10/02 熬夜，10/03 00:30–01:15 训练，02:00 才睡
  const s1 = night(at('2026-10-01', 23), STD_NIGHT);
  const s2 = night(at('2026-10-03', 2), [['core', 200], ['deep', 60], ['rem', 60], ['core', 100]]);
  const workout = { activityType: 'running', start: at('2026-10-03', 0, 30), end: at('2026-10-03', 1, 15) };
  const hr = [...hrSeries(at('2026-10-01', 22), at('2026-10-03', 10), 300, 65), ...hrSeries(workout.start, workout.end, 5, 160)].sort((a, b) => a.date - b.date);
  const input = { tier: 'A', profile: { birthYear: 1994, sex: 'male' }, rangeStart: at('2026-10-01', 20), asOf: at('2026-10-03', 12),
    sleep: [...s1, ...s2], inBed: [], heartRate: hr,
    sdnn: [at('2026-10-02', 3), at('2026-10-03', 5)].map((t) => ({ start: t, end: t + 60, value: 50 })),
    restingHR: [], respiratory: [], wristTemperature: [], oxygen: [], breathing: [], workouts: [workout] };
  const days = runStaged(input);
  const d1 = dayOf(days, '2026-10-02');
  assert.equal(d1.strain.workouts.length, 1, '凌晨 00:30 的训练算在 10/02 醒来的这个周期里');
  assert.ok(Math.abs(d1.sleep.tstHours - 470 / 60) < 1e-3, '跨零点的一晚完整计入，不被切成两天');
  // noop：按自然日聚合 → 23:00–24:00 的 1 小时睡眠归 10/01，其余归 10/02；凌晨训练归 10/03
  assert.equal(dayOf(days, '2026-10-03').strain.workouts.length, 0);
});

test('缺陷 7：稳健基线，导入历史后立即可用；单个异常夜不带偏基线', () => {
  const days = runStaged(scenario('2026-09-01', 35, (i) => (i === 20 ? { sdnn: [300, 310, 320] } : { sdnn: [50 + (i % 3), 55, 60 - (i % 2)] })));
  const last = days[days.length - 1];
  assert.equal(last.recovery.baselines.lnSDNN.n, 30);
  assert.equal(last.recovery.baselines.lnSDNN.calibrating, false);
  assert.ok(Math.abs(last.recovery.baselines.hrvMs - 55) < 0.6, `基线中位数不受 300 ms 异常夜影响：${last.recovery.baselines.hrvMs}`);
  // 第 2 晚起就有分数（向人群先验收缩，标注“基线建立中”）；noop 手表路径前 7 晚都不出分
  assert.equal(days[1].recovery.status, 'ok');
  assert.equal(days[1].recovery.baselines.lnSDNN.calibrating, true);
});

test('缺陷 8：直接用 Apple 分期；界面上核心 → LIGHT，深睡 → DEEP；短于 1 分钟的片段只在图上合并', () => {
  const stages = night(at('2026-10-01', 23), [['core', 100], ['awake', 0.5], ['core', 100], ['deep', 60], ['rem', 60], ['core', 159.5]]);
  const [s] = buildSessions(stages).filter((x) => x.kind === 'main');
  const m = sleepMetrics(s);
  assert.equal(m.stageMinutes.awake, 0.5, '统计时长用原始分期');
  const h = hypnogram(s.stages);
  assert.deepEqual(h.map((x) => x.label), ['LIGHT', 'DEEP', 'REM', 'LIGHT']);
});

test('缺陷 9：没戴表的夜晚不出恢复分数；白天的未佩戴时段不计负荷', () => {
  const days = runStaged(scenario('2026-10-01', 6, (i) => (i === 3 ? { skip: true } : {})));
  const miss = dayOf(days, '2026-10-05');
  assert.equal(miss.recovery.status, 'unworn');
  assert.equal(miss.recovery.score, null);
  // 有睡眠记录但睡眠期间没有 HRV → 不出分（不编数）
  const noHrv = dayOf(runStaged(scenario('2026-10-01', 6, (i) => (i === 5 ? { sdnn: [] } : {}))), '2026-10-07');
  assert.equal(noHrv.recovery.status, 'no-hrv');
  assert.equal(noHrv.recovery.score, null);
  // 白天 2 小时没有心率：这些分钟记为未佩戴，负荷贡献为 0
  const day0 = at('2026-10-02', 7);
  const pts = [...hrSeries(day0, day0 + 4 * H, 300, 120), ...hrSeries(day0 + 6 * H, day0 + 10 * H, 300, 120)];
  const g = buildMinuteGrid(pts, day0, day0 + 10 * H);
  const r = cycleLoadA({ grid: g, wake: day0, until: day0 + 10 * H, workouts: [], rest: 55, max: 185.6, sex: 'male' });
  assert.ok(r.unworn >= 120, `未佩戴分钟 ${r.unworn}`);
  assert.ok(r.counted <= 8 * 60);
});
