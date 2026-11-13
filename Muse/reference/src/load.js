// 负荷 Strain（PRD §5.10、§2.2 约束 B；代码 MinuteGrid.swift / LoadCalculator.swift / Strain.swift / MaxHeartRate.swift）。
// A 档：分钟时间线 + 按真实间隔积分的 Banister TRIMP。B/C 档：从训练记录和活动能量估算（M-06）。
import { CONFIG } from './config.js';
import { mean } from './stats.js';

/** 心率储备比 HRR%，截断在 [0, 1]（PRD §5.1）。 */
export function hrr(bpm, rest, max) {
  const reserve = max - rest;
  if (!(reserve > 0)) return 0;
  return Math.min(Math.max((bpm - rest) / reserve, 0), 1);
}

/** 每分钟 Banister TRIMP：只计 HRR ≥ 0.25（PRD §5.10 第 2 条）。 */
export function trimpPerMinute(x, sex, cfg = CONFIG) {
  if (x < cfg.trimpMinHRR) return 0;
  const m = x * 0.64 * Math.exp(1.92 * x);
  const f = x * 0.86 * Math.exp(1.67 * x);
  return sex === 'male' ? m : sex === 'female' ? f : (m + f) / 2;
}

/** Strain = min(21, 5.3 · ln(1 + TRIMP / 10))（PRD §5.10 第 4 条）。 */
export function strainFromTrimp(t, cfg = CONFIG) {
  return Math.min(cfg.strainMax, cfg.strainScale * Math.log(1 + Math.max(t, 0) / cfg.strainTrimpDivisor));
}

/** 心率区间 Z1…Z5 → 0…4；HRR < 0.5 为 null（PRD §5.1）。 */
export function zoneIndex(x) {
  if (x >= 0.9) return 4;
  if (x >= 0.8) return 3;
  if (x >= 0.7) return 2;
  if (x >= 0.6) return 1;
  if (x >= 0.5) return 0;
  return null;
}

/** 初始最大心率 208 − 0.7 × 年龄（Tanaka）；年龄未知按 35 岁。 */
export const tanaka = (birthYear, year) => 208 - 0.7 * (birthYear ? year - birthYear : 35);

/** 训练中 30 秒分桶均值的最大值（PRD §5.1“运动中 30 秒滑动均值”的近似，同 Vigor）。 */
export function observedPeak(samples) {
  if (!samples.length) return null;
  const t0 = Math.min(...samples.map((s) => s.date));
  const buckets = new Map();
  for (const s of samples) {
    const b = Math.trunc((s.date - t0) / 30);
    const cur = buckets.get(b) ?? [0, 0];
    cur[0] += s.bpm; cur[1] += 1;
    buckets.set(b, cur);
  }
  return Math.max(...[...buckets.values()].map(([a, n]) => a / n));
}

/**
 * 分钟网格：同一分钟的心率取平均。origin 向下取整到整分钟。
 * 返回 {origin, count, hr(Float64Array, NaN=无测量), prev, next}
 */
export function buildMinuteGrid(heartRate, origin, end) {
  const o = Math.floor(origin / 60) * 60;
  const count = Math.max(0, Math.ceil((end - o) / 60));
  const sum = new Float64Array(count);
  const n = new Uint32Array(count);
  for (const s of heartRate) {
    const i = Math.trunc((s.date - o) / 60);
    if (i < 0 || i >= count) continue;
    sum[i] += s.bpm; n[i] += 1;
  }
  const hr = new Float64Array(count);
  for (let i = 0; i < count; i++) hr[i] = n[i] ? sum[i] / n[i] : NaN;
  const prev = new Int32Array(count);
  const next = new Int32Array(count);
  let last = -1;
  for (let i = 0; i < count; i++) { if (!Number.isNaN(hr[i])) last = i; prev[i] = last; }
  let up = -1;
  for (let i = count - 1; i >= 0; i--) { if (!Number.isNaN(hr[i])) up = i; next[i] = up; }
  return { origin: o, count, hr, prev, next, index: (t) => Math.floor((t - o) / 60) };
}

/**
 * 分钟时间线（PRD §5.10 第 1 条、§2.2 约束 B）：
 * 有测量 → measured；相邻测量间隔 ≤ 15 分钟 → 线性插值；间隔 > 60 分钟（或一侧没有测量）→ 未佩戴，不计入；
 * 15–60 分钟 → 按静息心率处理（负荷约为 0）。Vigor 在这一段会先尝试“活动能量 → 心率”回归，Muse 不做（M-07）。
 */
export function timeline(grid, lo, hi, rest, cfg = CONFIG) {
  const out = [];
  for (let i = Math.max(0, lo); i < Math.min(grid.count, hi); i++) {
    const m = grid.hr[i];
    if (!Number.isNaN(m)) { out.push({ i, bpm: m, source: 'measured' }); continue; }
    const p = grid.prev[i];
    const q = grid.next[i];
    if (p < 0 || q < 0) { out.push({ i, bpm: null, source: 'unworn' }); continue; }
    const gap = q - p;
    if (gap <= cfg.interpolationGapMin) {
      out.push({ i, bpm: grid.hr[p] + (grid.hr[q] - grid.hr[p]) * ((i - p) / gap), source: 'interpolated' });
    } else if (gap > cfg.unwornGapMin) {
      out.push({ i, bpm: null, source: 'unworn' });
    } else {
      out.push({ i, bpm: rest, source: 'resting' });
    }
  }
  return out;
}

/** 对时间线积分：TRIMP、计入分钟、未佩戴分钟、区间分钟。 */
export function integrate(samples, rest, max, sex, cfg = CONFIG) {
  let trimp = 0; let counted = 0; let unworn = 0;
  const zones = [0, 0, 0, 0, 0];
  const bpms = [];
  for (const s of samples) {
    if (s.source === 'unworn' || s.bpm == null) { unworn++; continue; }
    counted++;
    bpms.push(s.bpm);
    const x = hrr(s.bpm, rest, max);
    trimp += trimpPerMinute(x, sex, cfg);
    const z = zoneIndex(x);
    if (z != null) zones[z]++;
  }
  return { trimp, counted, unworn, zones, meanHR: mean(bpms), peakHR: bpms.length ? Math.max(...bpms) : null };
}

/** A 档：一个周期的负荷与每次训练的负荷。 */
export function cycleLoadA({ grid, wake, until, workouts, rest, max, sex }, cfg = CONFIG) {
  const lo = grid.index(wake);
  const hi = Math.max(lo, grid.index(until));
  const day = integrate(timeline(grid, lo, hi, rest, cfg), rest, max, sex, cfg);
  const wl = workouts.map((w) => {
    const a = grid.index(w.start);
    const b = Math.max(a + 1, grid.index(w.end));
    const r = integrate(timeline(grid, a, b, rest, cfg), rest, max, sex, cfg);
    return {
      type: w.activityType, start: w.start, end: w.end, minutes: (w.end - w.start) / 60,
      trimp: r.trimp, strain: strainFromTrimp(r.trimp, cfg), zones: r.zones, meanHR: r.meanHR, peakHR: r.peakHR,
    };
  });
  // 全天心率曲线（供负荷页绘图）：每 5 分钟取一个点，未佩戴为 null
  const curve = [];
  for (let i = lo; i < hi; i += 5) {
    const v = grid.hr[i];
    curve.push([grid.origin + i * 60, Number.isNaN(v) ? null : Math.round(v)]);
  }
  return {
    trimp: day.trimp, strain: strainFromTrimp(day.trimp, cfg), counted: day.counted, unworn: day.unworn,
    zones: day.zones, workouts: wl, curve, method: 'minute-trimp',
  };
}

/**
 * B 档：训练记录（时长、平均心率）+ 非训练活动能量估算。M-06。
 * TRIMP_B = Σ 训练分钟 × f(HRR(平均心率)) + 0.075 × max(0, 非训练活动能量 − 300 kcal)
 */
export function cycleLoadB({ workouts, nonWorkoutKcal, rest, max, sex }, cfg = CONFIG) {
  const wl = workouts.map((w) => {
    const minutes = (w.end - w.start) / 60;
    const x = w.avgHR == null ? null : hrr(w.avgHR, rest, max);
    const trimp = x == null ? 0 : minutes * trimpPerMinute(x, sex, cfg);
    return { type: w.activityType, start: w.start, end: w.end, minutes, trimp, strain: strainFromTrimp(trimp, cfg), meanHR: w.avgHR, peakHR: w.maxHR };
  });
  const extra = nonWorkoutKcal == null ? 0 : cfg.trimpPerKcal * Math.max(0, nonWorkoutKcal - cfg.nonWorkoutKcalFloor);
  const trimp = wl.reduce((a, w) => a + w.trimp, 0) + extra;
  return { trimp, strain: strainFromTrimp(trimp, cfg), workouts: wl, nonWorkoutTrimp: extra, method: 'workout-estimate' };
}

/**
 * C 档：只有每日训练分钟和活动能量。M-06。
 * TRIMP_C = 训练分钟 × f(0.55) + 0.075 × max(0, 活动能量 − 8 × 训练分钟 − 300)
 */
export function dayLoadC({ workoutMinutes, activeKcal, sex }, cfg = CONFIG) {
  const w = workoutMinutes * trimpPerMinute(cfg.tierCWorkoutHRR, sex, cfg);
  const extra = activeKcal == null ? 0
    : cfg.trimpPerKcal * Math.max(0, activeKcal - cfg.tierCWorkoutKcalPerMin * workoutMinutes - cfg.nonWorkoutKcalFloor);
  const trimp = w + extra;
  return { trimp, strain: strainFromTrimp(trimp, cfg), workoutTrimp: w, nonWorkoutTrimp: extra, method: 'daily-estimate' };
}
