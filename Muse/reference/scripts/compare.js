// 三档对照：同一份数据分别按 A / B / C 档计算，与 Vigor 完整管线（逐拍 RMSSD）比较。
// 用法：node scripts/compare.js [fixtures 目录]（默认 fixtures/synthetic-seed42）
// 输出：golden/comparison.json，以及打印到终端的 Markdown 表格（COMPARISON.md 由它生成）。
import { writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readJSON, readSnapshot } from '../src/io.js';
import { toTierA, toTierB, toTierC, toTierH } from '../src/tiers.js';
import { run } from '../src/pipeline.js';
import { recoveryScore } from '../src/recovery.js';
import { CONFIG } from '../src/config.js';
import { dayKey, startOfDayKey } from '../src/time.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dir = process.argv[2] ?? join(root, 'fixtures/synthetic-seed42');
const snap = readSnapshot(dir);
const vigor = readJSON(join(dir, 'vigor.json'));

/** 可复现的伪随机数（mulberry32） */
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * 合成数据只有夜间 SDNN。真实的 S10 白天也会记录 SDNN（姿势、活动影响大、通常偏低）。
 * 为了量化 B/C 档“全天平均 SDNN”的偏差，给每天加 4 条日间读数：10/13/16/19 点，18–50 ms 均匀分布。
 */
function withDaytimeSDNN(s) {
  const r = rng(7);
  const extra = [];
  for (let t = startOfDayKey(dayKey(s.rangeStart)); t < s.rangeEnd; t += 86400) {
    for (const h of [10, 13, 16, 19]) {
      const start = t + h * 3600;
      extra.push({ start, end: start + 60, value: 18 + 32 * r() });
    }
  }
  return { ...s, hrvSDNN: [...s.hrvSDNN, ...extra].sort((a, b) => a.start - b.start) };
}

/**
 * Vigor 的合成数据里，SDNN 是独立抽取的随机数（和 RMSSD 的相关系数约 0.15），这不符合生理：
 * 同一晚的 SDNN 与 RMSSD 在真实数据里高度相关。为了估计 A 档在“像真实数据”时的偏差，
 * 把每晚睡眠窗口内的 SDNN 改成 RMSSD × exp(0.25 + N(0, 0.15))。这是假设，不是测量。
 */
function withCorrelatedSDNN(s, cycles) {
  const r = rng(11);
  const gauss = () => Math.sqrt(-2 * Math.log(r() || 1e-12)) * Math.cos(2 * Math.PI * r());
  const nights = cycles.filter((c) => c.rmssd != null);
  const hrvSDNN = s.hrvSDNN.map((x) => {
    const n = nights.find((c) => x.start >= c.sleepStart && x.start <= c.sleepEnd);
    return n ? { ...x, value: n.rmssd * Math.exp(0.25 + 0.15 * gauss()) } : x;
  });
  return { ...s, hrvSDNN };
}

/** 把恢复分数里的 z_hrv 换成 Vigor 的（其余输入不变），隔离出“HRV 输入不同”以外的偏差。 */
function oracleHRV(days, ref) {
  const R = new Map(ref.map((c) => [c.wakeDay, c]));
  return days.map((d) => {
    const v = R.get(d.wakeDay);
    if (!v || d.recovery.status === 'unworn' || v.zHRV == null || !d.recovery.penalties) return d;
    const rec = recoveryScore({ zHRV: v.zHRV, zRHR: d.recovery.z.rhr, zSleep: d.recovery.z.sleep, pen: d.recovery.penalties, illnessPossible: d.recovery.illness?.level === 'possiblyUnwell' });
    return { ...d, recovery: { ...d.recovery, score: rec.score, zone: rec.zone } };
  });
}

const mae = (pairs) => (pairs.length ? pairs.reduce((a, [x, y]) => a + Math.abs(x - y), 0) / pairs.length : null);
const maxErr = (pairs) => (pairs.length ? Math.max(...pairs.map(([x, y]) => Math.abs(x - y))) : null);

function pearson(pairs) {
  const n = pairs.length;
  if (n < 3) return null;
  const mx = pairs.reduce((a, [x]) => a + x, 0) / n;
  const my = pairs.reduce((a, [, y]) => a + y, 0) / n;
  let sxy = 0; let sxx = 0; let syy = 0;
  for (const [x, y] of pairs) { sxy += (x - mx) * (y - my); sxx += (x - mx) ** 2; syy += (y - my) ** 2; }
  return sxy / Math.sqrt(sxx * syy);
}

function compareTier(days, ref) {
  const R = new Map(ref.map((c) => [c.wakeDay, c]));
  const rec = []; let zoneSame = 0; let zoneTotal = 0; let onlyOne = 0;
  const strain = []; const tst = []; const perf = []; const sleepScore = [];
  for (const d of days) {
    const v = R.get(d.wakeDay);
    if (!v) continue;
    const s = d.recovery.score;
    if (s != null && v.recovery != null) {
      rec.push([s, v.recovery]);
      zoneTotal++;
      if (d.recovery.zone === v.zone) zoneSame++;
    } else if ((s == null) !== (v.recovery == null)) onlyOne++;
    if (d.strain?.strain != null) strain.push([d.strain.strain, v.strain]);
    if (d.sleep?.tstHours != null) tst.push([d.sleep.tstHours * 60, v.tstHours * 60]);
    if (d.sleep?.performance != null) perf.push([d.sleep.performance, v.sleepPerformance]);
    if (d.sleep?.score != null) sleepScore.push([d.sleep.score, v.sleepScore]);
  }
  const r2 = (x) => (x == null ? null : Math.round(x * 100) / 100);
  return {
    days: rec.length,
    recoveryMAE: r2(mae(rec)), recoveryMax: r2(maxErr(rec)), recoveryPearson: r2(pearson(rec)),
    zoneAgreement: zoneTotal ? r2((100 * zoneSame) / zoneTotal) : null, zoneDifferentDays: zoneTotal - zoneSame,
    scoredMismatchDays: onlyOne,
    strainMAE: r2(mae(strain)), strainMax: r2(maxErr(strain)),
    tstMAEmin: r2(mae(tst)), performanceMAE: r2(mae(perf)), sleepScoreMAE: r2(mae(sleepScore)),
  };
}

/** A 档与 Vigor 的逐项特征对照（用去掉 FIT/功率的 Vigor 结果，只检验移植本身）。 */
function parity(days, ref) {
  const R = new Map(ref.map((c) => [c.wakeDay, c]));
  const items = {
    'TST（分钟）': [(d) => d.sleep.tstHours * 60, (v) => v.tstHours * 60],
    '睡眠效率（%）': [(d) => d.sleep.efficiency * 100, (v) => v.efficiency * 100],
    'SRI': [(d) => d.sleep.sri, (v) => v.sri],
    '睡眠需求（分钟）': [(d) => d.sleep.need.total * 60, (v) => v.needHours * 60],
    '睡眠负债（分钟）': [(d) => d.sleep.debtAfterHours * 60, (v) => v.debtAfterHours * 60],
    'Sleep Performance（%）': [(d) => d.sleep.performance, (v) => v.sleepPerformance],
    '睡眠分': [(d) => d.sleep.score, (v) => v.sleepScore],
    '夜间静息心率（bpm）': [(d) => d.recovery.inputs.rhr, (v) => v.rhr],
    '呼吸率（次/分）': [(d) => d.recovery.inputs.respiratoryRate, (v) => v.respiratoryRate],
    '手腕温度偏差（°C）': [(d) => d.recovery.inputs.tempDelta, (v) => v.temperatureDelta],
    '血氧中位数（%）': [(d) => d.recovery.inputs.spo2Median, (v) => v.spo2Median],
    'TRIMP': [(d) => d.strain.trimp, (v) => v.trimp],
    'Strain': [(d) => d.strain.strain, (v) => v.strain],
  };
  const out = {};
  for (const [name, [a, b]] of Object.entries(items)) {
    const pairs = [];
    for (const d of days) {
      if (d.recovery.status === 'unworn') continue;
      const v = R.get(d.wakeDay);
      if (!v) continue;
      const x = a(d); const y = b(v);
      if (x != null && y != null) pairs.push([x, y]);
    }
    const within = (tol) => pairs.filter(([x, y]) => Math.abs(x - y) <= tol).length;
    out[name] = { n: pairs.length, mae: Math.round(mae(pairs) * 1000) / 1000, max: Math.round(maxErr(pairs) * 1000) / 1000, exactWithin001: within(0.01) };
  }
  return out;
}

const datasets = [
  ['原始合成数据（只有夜间 SDNN，且 SDNN 与 RMSSD 无关）', snap],
  ['合成数据 + 每天 4 条日间 SDNN', withDaytimeSDNN(snap)],
  ['假设：夜间 SDNN 与 RMSSD 相关（r≈0.8）+ 日间 SDNN', withDaytimeSDNN(withCorrelatedSDNN(snap, vigor.parityCycles))],
];
const result = { generatedFrom: dir, reference: 'Vigor 完整管线（逐拍 RMSSD，含 FIT 骑行）', datasets: [] };
for (const [name, s] of datasets) {
  const tiers = {
    A: run(toTierA(s)), B: run(toTierB(s)), C: run(toTierC(s)), H: run(toTierH(s)),
    'H（静息心率取夜间最低小时均值）': run(toTierH(s), { ...CONFIG, tierHRestingSource: 'hourlyMin' }),
  };
  result.datasets.push({
    name,
    tiers: Object.fromEntries(Object.entries(tiers).map(([k, days]) => [k, compareTier(days, vigor.cycles)])),
    parityA: parity(tiers.A, vigor.parityCycles),
    parityH: parity(tiers.H, vigor.parityCycles),
    oracleA: compareTier(oracleHRV(tiers.A, vigor.cycles), vigor.cycles),
  });
}
// Vigor 自己的分区分布，作为参照
const zones = { green: 0, yellow: 0, red: 0 };
vigor.cycles.forEach((c) => { if (c.zone) zones[c.zone]++; });
result.vigorZones = zones;
result.vigorHrvMethods = vigor.cycles.reduce((a, c) => ({ ...a, [c.hrvMethod]: (a[c.hrvMethod] ?? 0) + 1 }), {});

writeFileSync(join(root, 'golden/comparison.json'), JSON.stringify(result, null, 2) + '\n');

// —— Markdown ——
const lines = [];
lines.push(`对照基准：${result.reference}；Vigor 分区分布 绿 ${zones.green} / 黄 ${zones.yellow} / 红 ${zones.red}。`);
for (const ds of result.datasets) {
  lines.push('', `### ${ds.name}`, '', '| 档 | 天数 | 恢复 MAE | 恢复最大差 | 相关系数 | 分区一致率 | 分区不同天数 | 负荷 MAE | 负荷最大差 | TST MAE（分钟） | Performance MAE | 睡眠分 MAE |', '|---|---|---|---|---|---|---|---|---|---|---|---|');
  for (const [k, m] of Object.entries(ds.tiers)) {
    lines.push(`| ${k} | ${m.days} | ${m.recoveryMAE} | ${m.recoveryMax} | ${m.recoveryPearson} | ${m.zoneAgreement}% | ${m.zoneDifferentDays} | ${m.strainMAE} | ${m.strainMax} | ${m.tstMAEmin} | ${m.performanceMAE} | ${m.sleepScoreMAE} |`);
  }
  const o = ds.oracleA;
  lines.push(`| A，HRV 换成 Vigor 的 z_hrv | ${o.days} | ${o.recoveryMAE} | ${o.recoveryMax} | ${o.recoveryPearson} | ${o.zoneAgreement}% | ${o.zoneDifferentDays} | — | — | — | — | — |`);
}
lines.push('', '### A 档逐项特征 vs Vigor（去掉 FIT 骑行与功率，只检验移植）', '', '| 特征 | 天数 | 平均绝对差 | 最大差 | 差 ≤ 0.01 的天数 |', '|---|---|---|---|---|');
for (const [k, m] of Object.entries(result.datasets[0].parityA)) lines.push(`| ${k} | ${m.n} | ${m.mae} | ${m.max} | ${m.exactWithin001} |`);
lines.push('', '### H 档逐项特征 vs Vigor（去掉 FIT 骑行与功率；H 档本来就是近似，看差多少）', '', '| 特征 | 天数 | 平均绝对差 | 最大差 | 差 ≤ 0.01 的天数 |', '|---|---|---|---|---|');
for (const [k, m] of Object.entries(result.datasets[0].parityH)) lines.push(`| ${k} | ${m.n} | ${m.mae} | ${m.max} | ${m.exactWithin001} |`);
console.log(lines.join('\n'));
