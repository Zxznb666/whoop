// 核心数学：与 Vigor 规格逐条对应的单元测试。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { percentile, median, mad } from '../src/stats.js';
import { baselineStat, zScore } from '../src/baseline.js';
import { recoveryScore, penalties, zone, BASELINE_SCORE, illnessSignals, loadTarget, acwr } from '../src/recovery.js';
import { strainFromTrimp, trimpPerMinute, hrr, zoneIndex, tanaka } from '../src/load.js';
import { buildSessions, sleepMetrics, sleepNeed, nextDebt, sleepScore, sri } from '../src/sleep.js';
import { at, night, STD_NIGHT, H, M } from './helpers/build.js';

const near = (a, b, tol = 1e-6, msg) => assert.ok(Math.abs(a - b) <= tol, msg ?? `${a} ≉ ${b}（容差 ${tol}）`);
const profile = { birthYear: 1994, sex: 'male' };

test('百分位：线性插值，与 numpy 默认一致', () => {
  assert.equal(percentile([1, 2, 3, 4], 0.5), 2.5);
  near(percentile([10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110], 0.1), 20);
  assert.equal(median([3, 1, 2]), 2);
  assert.equal(mad([1, 2, 3, 4, 100]), 1);
});

test('基线：满 30 晚时 = 中位数与 1.4826 × MAD；σ 有下限', () => {
  const v = Array.from({ length: 40 }, (_, i) => 12 + (i % 5));
  const s = baselineStat(v, 'respiratoryRate', profile, 2026);
  assert.equal(s.n, 30);
  assert.equal(s.mu, 14);
  near(s.sigma, 1.4826 * 1);
  const flat = baselineStat(new Array(30).fill(50), 'restingHeartRate', profile, 2026);
  assert.equal(flat.sigma, 1.5, 'σ 下限 1.5 bpm');
});

test('基线：不足 30 晚时向人群先验收缩（n₀ = 7）', () => {
  const s = baselineStat([60, 60, 60], 'restingHeartRate', profile, 2026);
  near(s.mu, (7 * 55 + 3 * 60) / 10);
  assert.equal(s.calibrating, true);
  const t = baselineStat([], 'wristTemperature', profile, 2026);
  assert.equal(t.mu, null, '手腕温度没有先验 μ');
});

test('恢复：raw = 0 时约 58.66%；分区边界 67 / 33', () => {
  near(BASELINE_SCORE, 58.66, 0.01);
  near(recoveryScore({ zHRV: 0, zRHR: 0, zSleep: 0 }).score, 58.66, 0.01);
  assert.equal(zone(67), 'green');
  assert.equal(zone(66.99), 'yellow');
  assert.equal(zone(33), 'red');
  assert.equal(zone(33.01), 'yellow');
});

test('恢复：没有 HRV 就不出分', () => {
  assert.equal(recoveryScore({ zHRV: null, zRHR: 1, zSleep: 1 }), null);
});

test('恢复：缺失分量时权重按比例放大；z 截断到 ±3', () => {
  const r = recoveryScore({ zHRV: 1, zRHR: null, zSleep: null });
  near(r.weights.HRV, 1);
  near(r.score, 100 / (1 + Math.exp(-(1.4 * 1 + 0.35))));
  near(recoveryScore({ zHRV: 10 }).score, recoveryScore({ zHRV: 3 }).score);
});

test('恢复：矛盾信号（z_hrv > 2 且 z_rhr < −1）时 z_hrv 按 1 封顶', () => {
  const r = recoveryScore({ zHRV: 2.5, zRHR: -1.5, zSleep: 0 });
  assert.equal(r.contradiction, true);
  assert.equal(r.zUsed.hrv, 1);
});

test('恢复：Shapley 贡献之和 = 分数 − 58.66', () => {
  const pen = penalties({ zResp: 2, tempDelta: 0.6, spo2Median: 93, breathingElevated: true });
  const r = recoveryScore({ zHRV: -0.8, zRHR: 0.4, zSleep: 1.2, pen });
  near(r.contributions.reduce((a, c) => a + c.points, 0), r.uncapped - BASELINE_SCORE, 1e-9);
});

test('扣分项：连续函数与上限（PRD §5.8.2）', () => {
  const p = penalties({ zResp: 1.5, tempDelta: 0.55, spo2Median: 93, breathingElevated: false });
  near(p.resp, 0.15); near(p.temp, 0.4); near(p.spo2, 0.2); assert.equal(p.bd, 0);
  const cap = penalties({ zResp: 9, tempDelta: 5, spo2Median: 80, breathingElevated: true });
  assert.deepEqual(cap, { resp: 0.6, temp: 1.2, spo2: 0.4, bd: 0.2 });
});

test('生病预警：T + 任一，或 R、H、C 同时', () => {
  const st = { mu: 52, sigma: 2 };
  assert.equal(illnessSignals({ tempDelta: 0.6, zResp: 1.6, zHRV: 0, rhr: 50, rhrStat: st }).attention, true);
  assert.equal(illnessSignals({ tempDelta: 0.1, zResp: 1.6, zHRV: -2, rhr: 50, rhrStat: st }).attention, false);
  assert.equal(illnessSignals({ tempDelta: 0.1, zResp: 1.6, zHRV: -2, rhr: 57, rhrStat: st }).attention, true);
});

test('负荷：Strain 锚点（PRD §5.10）与 21 封顶', () => {
  near(strainFromTrimp(20), 5.82, 0.01);
  near(strainFromTrimp(87), 12.0, 0.05);
  near(strainFromTrimp(300), 18.2, 0.05);
  assert.equal(strainFromTrimp(5000), 21);
  assert.equal(strainFromTrimp(0), 0);
});

test('负荷：HRR < 0.25 的分钟不计；区间按 HRR 划分', () => {
  assert.equal(trimpPerMinute(0.24, 'male'), 0);
  near(trimpPerMinute(0.5, 'male'), 0.5 * 0.64 * Math.exp(0.96));
  near(hrr(120, 50, 190), 0.5);
  assert.equal(zoneIndex(0.49), null);
  assert.equal(zoneIndex(0.95), 4);
  near(tanaka(1994, 2026), 185.6);
});

test('负荷目标：按分区给区间，ACWR > 1.3 下调 2', () => {
  assert.deepEqual(loadTarget('green', 1.0), [14, 18]);
  assert.deepEqual(loadTarget('red', 1.5), [0, 8]);
  assert.equal(acwr([1, 2, 3]), null);
  near(acwr([...new Array(21).fill(10), ...new Array(7).fill(20)]), 20 / ((21 * 10 + 7 * 20) / 28));
});

test('睡眠会话：间隔 ≤ 45 分钟合并；45–120 分钟且在夜间窗口内也合并', () => {
  const a = night(at('2026-11-10', 23), [['core', 120]]);
  const b = night(at('2026-11-11', 1, 40), [['core', 300]]); // 间隔 40 分钟
  const s = buildSessions([...a, ...b]);
  assert.equal(s.length, 1);
  const c = night(at('2026-11-11', 3, 0), [['core', 240]]);
  const s2 = buildSessions([...a, ...c]); // 间隔 120 分钟，夜间窗口内
  assert.equal(s2.length, 1);
  assert.equal(s2[0].kind, 'main');
});

test('睡眠会话：Apple Watch 优先于其他 App 的重叠分期', () => {
  const w = night(at('2026-11-10', 23), STD_NIGHT);
  const other = [{ start: w[0].start, end: w[0].end, stage: 'deep', productType: null, sourceBundleID: 'x' }];
  const [s] = buildSessions([...w, ...other]).filter((x) => x.kind === 'main');
  assert.equal(s.stages.filter((x) => x.stage === 'deep').length, 2);
});

test('睡眠指标：TST、效率（有在床）、修复性睡眠', () => {
  const stages = night(at('2026-11-10', 23), STD_NIGHT);
  const inBed = [{ start: at('2026-11-10', 22, 40), end: at('2026-11-11', 7, 5) }];
  const [s] = buildSessions(stages, inBed);
  const m = sleepMetrics(s);
  near(m.totalSleepHours, (480 - 10) / 60);
  near(m.efficiency, (470 * 60) / (s.end - at('2026-11-10', 22, 40)));
  near(m.restorativeHours, 180 / 60);
  assert.equal(m.awakenings, 1);
  assert.equal(m.sleepLatencyMinutes, 20);
});

test('睡眠需求与负债：负荷追加、小睡抵扣、还债上限；负债递推', () => {
  const n = sleepNeed({ previousStrain: 15, napHours: 0.5, previousDebt: 3 });
  near(n.loadAddition, 28 / 60);
  near(n.napCredit, 0.4);
  near(n.repayment, 0.9);
  near(n.total, 7.5 + 28 / 60 - 0.4 + 0.9);
  near(nextDebt(2, 7.5, 6), 0.8 * 2 + 1.5);
  assert.equal(nextDebt(0, 7.5, 9), 0, '负债最低为 0');
  assert.equal(sleepNeed({ previousStrain: 30, napHours: 0, previousDebt: 100 }).repayment, 2);
});

test('睡眠分：缺 SRI 时权重按比例分配；Performance 封顶 100%', () => {
  const s = sleepScore({ tstHours: 9, napCreditHours: 0, needHours: 8, efficiency: 0.95, sriValue: null, zRestorative: 0 });
  assert.equal(s.performance, 100);
  near(s.score, (100 * (0.55 * 1 + 0.15 * 1 + 0.15 * 0.5)) / 0.85);
});

test('SRI：每天同一时段睡觉 → 100；不足 5 天 → null', () => {
  const st = [];
  for (let d = 1; d <= 8; d++) {
    const day = `2026-11-${String(d).padStart(2, '0')}`;
    st.push(...night(at(day, 23), [['core', 480]]));
    st.push({ start: at(day, 23) + 480 * M, end: at(day, 23) + 960 * M, stage: 'awake', productType: 'Watch7,1' });
  }
  const end = at('2026-11-09', 7);
  near(sri(st, end), 100, 1e-9);
  assert.equal(sri(st.slice(0, 4), at('2026-11-03', 7)), null);
});

test('z-score：缺基线返回 null', () => {
  assert.equal(zScore(1, { mu: null, sigma: 1 }), null);
  assert.equal(zScore(3, { mu: 1, sigma: 2 }), 1);
});
