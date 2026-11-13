// 睡眠：会话拼装（PRD §5.2）、基础指标（§5.9.1）、规律性 SRI（§5.9.2）、需求与负债（§5.9.3）、睡眠分（§5.9.4）。
// 算法按 Vigor 的 SleepSessionBuilder / SleepMetrics / SleepRegularity / SleepNeed / SleepScore 重新实现。
import { CONFIG } from './config.js';
import { dayKey, localHour } from './time.js';
import { clamp } from './stats.js';

export const ASLEEP = new Set(['core', 'deep', 'rem', 'asleepUnspecified']);
export const isAsleep = (s) => ASLEEP.has(s.stage);

/** 来源优先级：Apple Watch（0）> iPhone（1）> 其他（2）。PRD §5.2 第 1 条 */
export function sourceRank(s) {
  if (s.productType?.startsWith('Watch')) return 0;
  if (s.productType?.startsWith('iPhone')) return 1;
  return 2;
}

const overlaps = (a, b) => a.start < b.end && b.start < a.end;

/** 时间上被更高优先级来源覆盖的分期样本丢弃。 */
export function applySourcePriority(samples) {
  const s = [...samples].sort((a, b) => a.start - b.start);
  const drop = new Array(s.length).fill(false);
  for (let i = 0; i < s.length; i++) {
    for (let j = i + 1; j < s.length && s[j].start < s[i].end; j++) {
      if (!overlaps(s[i], s[j])) continue;
      const ri = sourceRank(s[i]);
      const rj = sourceRank(s[j]);
      if (ri < rj) drop[j] = true;
      else if (rj < ri) drop[i] = true;
    }
  }
  return s.filter((_, i) => !drop[i]);
}

/** 同一来源重叠时保留较晚（创建时间，缺失时用结束时间）的一条。PRD §5.2 第 2 条 */
export function removeSameSourceOverlaps(samples) {
  const s = [...samples].sort((a, b) => a.start - b.start);
  const drop = new Array(s.length).fill(false);
  const recency = (x) => x.creationDate ?? x.end;
  const same = (a, b) => sourceRank(a) === sourceRank(b) && (a.sourceBundleID ?? null) === (b.sourceBundleID ?? null);
  for (let i = 0; i < s.length; i++) {
    if (drop[i]) continue;
    for (let j = i + 1; j < s.length && s[j].start < s[i].end; j++) {
      if (!drop[j] && same(s[i], s[j]) && overlaps(s[i], s[j])) {
        if (recency(s[j]) > recency(s[i])) { drop[i] = true; break; }
        drop[j] = true;
      }
    }
  }
  return s.filter((_, i) => !drop[i]);
}

/** 区间并集时长（秒），重叠只计一次。 */
export function unionSeconds(samples) {
  const iv = samples.map((x) => [x.start, x.end]).sort((a, b) => a[0] - b[0]);
  let total = 0;
  let run = null;
  for (const [a, b] of iv) {
    if (!run) { run = [a, b]; continue; }
    if (a <= run[1]) run[1] = Math.max(run[1], b);
    else { total += run[1] - run[0]; run = [a, b]; }
  }
  if (run) total += run[1] - run[0];
  return total;
}

function isNightWindow(t, cfg) {
  const h = localHour(t, cfg);
  return h >= cfg.nightWindowStartHour || h < cfg.nightWindowEndHour;
}

/**
 * 把分期样本拼成会话，并选出每晚的主睡眠。
 * @param stages 分期样本 {start,end,stage,productType?,sourceBundleID?,creationDate?}，单位秒
 * @param inBed  在床样本 {start,end}
 * @returns 按开始时间排序的会话 {start,end,bedtime,stages,asleepSeconds,wakeDay,nightKey,kind}
 */
export function buildSessions(stages, inBed = [], cfg = CONFIG) {
  const dedup = removeSameSourceOverlaps(applySourcePriority(stages.filter((s) => s.stage !== 'inBed')));
  const sorted = [...dedup].sort((a, b) => a.start - b.start);

  // 第 3 步：碎片合并
  const groups = [];
  let groupEnd = -Infinity;
  for (const s of sorted) {
    if (!groups.length) { groups.push([s]); groupEnd = s.end; continue; }
    const gap = s.start - groupEnd;
    const night = isNightWindow(groupEnd, cfg) && isNightWindow(s.start, cfg);
    if (gap <= cfg.sessionMergeGapMin * 60 || (gap <= cfg.segmentedSleepMaxGapMin * 60 && night)) {
      groups[groups.length - 1].push(s);
      groupEnd = Math.max(groupEnd, s.end);
    } else {
      groups.push([s]);
      groupEnd = s.end;
    }
  }

  // 第 5 步：边界
  const sessions = [];
  for (const g of groups) {
    const asleep = g.filter(isAsleep);
    if (!asleep.length) continue;
    const start = Math.min(...asleep.map((x) => x.start));
    const end = Math.max(...asleep.map((x) => x.end));
    const inside = g.filter((x) => x.start >= start && x.end <= end).sort((a, b) => a.start - b.start);
    const bedStarts = inBed.filter((b) => b.end > start && b.start < end).map((b) => b.start);
    const asleepSeconds = unionSeconds(inside.filter(isAsleep));
    if (asleepSeconds < cfg.napMinMinutes * 60) continue;
    const mid = start + (end - start) / 2;
    sessions.push({
      start, end,
      bedtime: bedStarts.length ? Math.min(...bedStarts) : null,
      stages: inside,
      asleepSeconds,
      wakeDay: dayKey(end, cfg),
      nightKey: dayKey(mid - cfg.nightKeyShiftHours * 3600, cfg),
      kind: 'nap',
    });
  }

  // 第 4 步：每个夜晚键最多一个主睡眠
  const best = new Map();
  sessions.forEach((s, i) => {
    const midHour = localHour(s.start + (s.end - s.start) / 2, cfg);
    const eligible = s.asleepSeconds >= cfg.mainSleepMinHours * 3600
      && !(midHour >= cfg.napOnlyStartHour && midHour < cfg.napOnlyEndHour);
    if (!eligible) return;
    const cur = best.get(s.nightKey);
    if (cur != null && sessions[cur].asleepSeconds >= s.asleepSeconds) return;
    best.set(s.nightKey, i);
  });
  sessions.forEach((s, i) => { s.kind = best.get(s.nightKey) === i ? 'main' : 'nap'; });
  return sessions.sort((a, b) => a.start - b.start);
}

/** H 档：只有整晚会话的起止和各分期总量时的睡眠指标；需要逐段时间线的量为 null。 */
export function sleepMetricsFromTotals(session) {
  const tst = session.asleepSeconds;
  const t = session.totals;
  const span = session.end - session.start;
  return {
    totalSleepHours: tst / 3600,
    efficiency: span > 0 ? tst / span : 0,
    efficiencyIsSleepPeriod: true,
    sleepLatencyMinutes: null,
    wasoMinutes: Math.max(0, (span - tst) / 60),
    awakenings: null,
    remLatencyMinutes: null,
    restorativeHours: (t.deep + t.rem) / 3600,
    restorativeFraction: tst > 0 ? (t.deep + t.rem) / tst : 0,
    stageMinutes: { awake: t.awake / 60, rem: t.rem / 60, light: t.core / 60, deep: t.deep / 60 },
  };
}

/** 基础睡眠指标（PRD §5.9.1）。 */
export function sleepMetrics(session, cfg = CONFIG) {
  const tst = session.asleepSeconds;
  const inBed = session.bedtime != null && session.bedtime <= session.start ? session.bedtime : null;
  const denom = session.end - (inBed ?? session.start);
  const sum = (stage) => session.stages.filter((x) => x.stage === stage).reduce((a, x) => a + x.end - x.start, 0);
  const deep = sum('deep');
  const rem = sum('rem');
  const core = sum('core') + sum('asleepUnspecified');
  const awake = sum('awake');
  const firstRem = session.stages.find((x) => x.stage === 'rem');
  return {
    totalSleepHours: tst / 3600,
    efficiency: denom > 0 ? tst / denom : 0,
    efficiencyIsSleepPeriod: inBed == null,
    sleepLatencyMinutes: inBed == null ? null : (session.start - inBed) / 60,
    wasoMinutes: Math.max(0, (session.end - session.start - tst) / 60),
    awakenings: session.stages.filter((x) => x.stage === 'awake' && x.end - x.start >= cfg.awakeningMinMinutes * 60).length,
    remLatencyMinutes: firstRem ? (firstRem.start - session.start) / 60 : null,
    restorativeHours: (deep + rem) / 3600,
    restorativeFraction: tst > 0 ? (deep + rem) / tst : 0,
    stageMinutes: { awake: awake / 60, rem: rem / 60, light: core / 60, deep: deep / 60 },
  };
}

/**
 * 睡眠规律指数 SRI（PRD §5.9.2）。返回 −100…100，数据不足为 null。
 * @param stages 原始分期样本（全部来源，含清醒），只用结束时间在 (endingAt − 7 天, endingAt] 内的
 */
export function sri(stages, endingAt, cfg = CONFIG) {
  const days = cfg.sriDays;
  const total = days * 1440;
  const start = endingAt - days * 86400;
  const state = new Uint8Array(total); // 0 未知，1 醒，2 睡
  for (const s of stages) {
    if (!(s.end <= endingAt && s.end > start) || s.stage === 'inBed') continue;
    const fill = s.stage === 'awake' ? 1 : 2;
    const first = Math.max(0, Math.trunc((s.start - start) / 60));
    const last = Math.min(total, Math.ceil((s.end - start) / 60));
    for (let i = first; i < last; i++) if (fill === 2 || state[i] === 0) state[i] = fill;
  }
  let covered = 0;
  for (let d = 0; d < days; d++) {
    for (let i = d * 1440; i < (d + 1) * 1440; i++) if (state[i]) { covered++; break; }
  }
  let comparable = 0;
  let agree = 0;
  for (let i = 0; i < total - 1440; i++) {
    const a = state[i];
    const b = state[i + 1440];
    if (!a || !b) continue;
    comparable++;
    if (a === b) agree++;
  }
  if (covered < cfg.sriMinDays || !comparable) return null;
  return -100 + 200 * (agree / comparable);
}

/** 睡眠需求的构成（PRD §5.9.3），单位小时。 */
export function sleepNeed({ previousStrain, napHours, previousDebt }, cfg = CONFIG) {
  const loadAddition = previousStrain == null ? 0
    : Math.min(cfg.loadAdditionMaxMin, cfg.loadAdditionMinPerStrain * Math.max(0, previousStrain - cfg.loadAdditionStrainFloor)) / 60;
  const napCredit = napHours * cfg.napCreditFactor;
  const baseNeed = cfg.baseSleepNeedHours + loadAddition - napCredit;
  const repayment = Math.min(cfg.maxRepaymentHours, cfg.repaymentRate * previousDebt);
  return { base: cfg.baseSleepNeedHours, loadAddition, napCredit, repayment, baseNeed, total: baseNeed + repayment };
}

/** 负债递推：D_t = clamp(λ·D_(t−1) + (N0_t − TST_t), 0, 10)。 */
export function nextDebt(previousDebt, baseNeed, tstHours, cfg = CONFIG) {
  return clamp(cfg.debtDecay * previousDebt + (baseNeed - tstHours), 0, cfg.maxDebtHours);
}

/**
 * 睡眠分（PRD §5.9.4）。缺失的分量（SRI、修复分、效率）按比例把权重分给其余分量。
 * efficiency 传 null 表示没有效率数据。
 */
export function sleepScore({ tstHours, napCreditHours, needHours, efficiency, sriValue, zRestorative }, cfg = CONFIG) {
  const w = cfg.sleepWeights;
  const duration = needHours > 0 ? Math.min(1, (tstHours + napCreditHours) / needHours) : 0;
  const parts = [[duration, w.duration]];
  const eff = efficiency == null ? null : clamp((efficiency - 0.75) / 0.20, 0, 1);
  if (eff != null) parts.push([eff, w.efficiency]);
  const consistency = sriValue == null ? null : Math.max(0, sriValue) / 100;
  if (consistency != null) parts.push([consistency, w.consistency]);
  const restorative = zRestorative == null ? null : clamp(0.5 + 0.25 * zRestorative, 0, 1);
  if (restorative != null) parts.push([restorative, w.restorative]);
  const wsum = parts.reduce((a, [, x]) => a + x, 0);
  const score = (100 * parts.reduce((a, [v, x]) => a + v * x, 0)) / wsum;
  return {
    score,
    performance: duration * 100,
    components: { duration, efficiency: eff, consistency, restorative },
    zSleep: (score - cfg.sleepScoreCenter) / cfg.sleepScoreScale,
  };
}

/** 睡眠图显示用分期：不足 1 分钟的片段并入较长的相邻片段（只影响显示，PRD §5.2）。 */
export function hypnogram(stages, cfg = CONFIG) {
  let seg = stages.map((s) => ({ start: s.start, end: s.end, stage: s.stage })).sort((a, b) => a.start - b.start);
  const dur = (s) => s.end - s.start;
  for (;;) {
    if (seg.length <= 1) break;
    let idx = 0;
    seg.forEach((s, i) => { if (dur(s) < dur(seg[idx])) idx = i; });
    if (dur(seg[idx]) >= cfg.hypnogramMinMinutes * 60) break;
    const prev = idx > 0 ? idx - 1 : null;
    const next = idx < seg.length - 1 ? idx + 1 : null;
    const nb = prev != null && next != null ? (dur(seg[prev]) >= dur(seg[next]) ? prev : next) : (prev ?? next);
    if (nb < idx) seg[nb].end = seg[idx].end; else seg[nb].start = seg[idx].start;
    seg.splice(idx, 1);
    for (let i = seg.length - 1; i > 0; i--) {
      if (seg[i - 1].stage === seg[i].stage) { seg[i - 1].end = seg[i].end; seg.splice(i, 1); }
    }
  }
  // 界面命名：核心 → LIGHT，深睡 → SWS(DEEP)
  const label = { awake: 'AWAKE', rem: 'REM', core: 'LIGHT', asleepUnspecified: 'LIGHT', deep: 'DEEP' };
  return seg.map((s) => ({ ...s, label: label[s.stage] }));
}
