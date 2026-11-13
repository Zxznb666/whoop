// 恢复分数（PRD §5.8，代码 RecoveryScorer.swift）。
import { CONFIG } from './config.js';
import { clamp } from './stats.js';

/** 连续扣分项（PRD §5.8.2）。缺失的输入扣 0。 */
export function penalties({ zResp, tempDelta, spo2Median, breathingElevated }) {
  return {
    resp: zResp == null ? 0 : Math.min(0.6, 0.3 * Math.max(0, zResp - 1.0)),
    temp: tempDelta == null ? 0 : Math.min(1.2, (0.8 * Math.max(0, tempDelta - 0.3)) / 0.5),
    spo2: spo2Median == null ? 0 : Math.min(0.4, 0.1 * Math.max(0, 95 - spo2Median)),
    bd: breathingElevated ? 0.2 : 0,
  };
}

export function zone(score, cfg = CONFIG) {
  if (score >= cfg.zoneGreenMin) return 'green';
  if (score <= cfg.zoneRedMax) return 'red';
  return 'yellow';
}

const logistic = (raw, cfg) => 100 / (1 + Math.exp(-(cfg.logisticK * raw + cfg.logisticOffset)));

/** raw = 0 时的分数，约 58.66 */
export const BASELINE_SCORE = logistic(0, CONFIG);

/**
 * @param zHRV 必填（没有就不出分，返回 null）
 * @param zRHR,zSleep 可缺；缺失时其余权重按比例放大
 * @param pen penalties() 的结果
 */
export function recoveryScore({ zHRV, zRHR = null, zSleep = null, pen = { resp: 0, temp: 0, spo2: 0, bd: 0 }, illnessPossible = false }, cfg = CONFIG) {
  if (zHRV == null) return null;
  let h = clamp(zHRV, -cfg.zClip, cfg.zClip);
  const r = zRHR == null ? null : clamp(zRHR, -cfg.zClip, cfg.zClip);
  const s = zSleep == null ? null : clamp(zSleep, -cfg.zClip, cfg.zClip);
  let contradiction = false;
  if (h > 2 && r != null && r < -1) { h = 1; contradiction = true; }

  const base = [['HRV', h, cfg.weights.hrv]];
  if (r != null) base.push(['RHR', r, cfg.weights.rhr]);
  if (s != null) base.push(['SLEEP', s, cfg.weights.sleep]);
  const wsum = base.reduce((a, x) => a + x[2], 0);
  const weights = Object.fromEntries(base.map(([n, , w]) => [n, w / wsum]));

  const players = [
    ...base.map(([name, z]) => ({ name, z })),
    { name: 'RESP', p: pen.resp }, { name: 'TEMP', p: pen.temp },
    { name: 'SPO2', p: pen.spo2 }, { name: 'BD', p: pen.bd },
  ];
  const value = (mask) => {
    let raw = 0;
    players.forEach((pl, i) => {
      if (!(mask & (1 << i))) return;
      if (pl.z != null) raw += weights[pl.name] * pl.z; else raw -= pl.p;
    });
    return logistic(raw, cfg);
  };
  const n = players.length;
  const all = (1 << n) - 1;
  const uncapped = value(all);
  const capped = illnessPossible && uncapped > cfg.illnessCap;
  const score = capped ? cfg.illnessCap : uncapped;
  const raw = Math.log(uncapped / (100 - uncapped)) / cfg.logisticK - cfg.logisticOffset / cfg.logisticK;
  return {
    score, uncapped, raw, zone: zone(score, cfg), capped, contradiction,
    zUsed: { hrv: h, rhr: r, sleep: s }, weights, penalties: pen,
    contributions: shapley(n, value).map((v, i) => ({ component: players[i].name, points: v })),
  };
}

/** 精确 Shapley 值（PRD §5.8.4）。各项之和 = 未封顶分数 − 58.66。 */
export function shapley(n, value) {
  const values = Array.from({ length: 1 << n }, (_, m) => value(m));
  const fact = [1];
  for (let k = 1; k <= n; k++) fact[k] = fact[k - 1] * k;
  const phi = new Array(n).fill(0);
  for (let p = 0; p < n; p++) {
    for (let m = 0; m < 1 << n; m++) {
      if (m & (1 << p)) continue;
      let size = 0;
      for (let b = m; b; b &= b - 1) size++;
      phi[p] += (fact[size] * fact[n - size - 1] / fact[n]) * (values[m | (1 << p)] - values[m]);
    }
  }
  return phi;
}

/** 生病预警信号与“注意”条件（PRD §5.12.1）。 */
export function illnessSignals({ tempDelta, zResp, zHRV, rhr, rhrStat }, cfg = CONFIG) {
  const c = cfg.illness;
  const t = (tempDelta ?? 0) >= c.tempDelta;
  const r = (zResp ?? -Infinity) >= c.zResp;
  const h = (zHRV ?? Infinity) <= c.zHRV;
  const hr = rhr != null && rhrStat?.mu != null && rhr >= rhrStat.mu + c.rhrSigmas * rhrStat.sigma;
  const attention = t ? (r || h || hr) : (r && h && hr);
  return { t, r, h, hr, attention };
}

/** 负荷目标区间（PRD §5.11）：由恢复分区决定，ACWR > 1.3 时整体下调 2。 */
export function loadTarget(zoneName, acwr, cfg = CONFIG) {
  const [lo, hi] = cfg.loadTargets[zoneName];
  if (acwr != null && acwr > cfg.acwrHigh) return [Math.max(0, lo - 2), Math.max(0, hi - 2)];
  return [lo, hi];
}

/** ACWR = 最近 7 天平均 TRIMP ÷ 最近 28 天平均 TRIMP（输入为今天之前的 TRIMP，按时间升序）。 */
export function acwr(previousTrimps) {
  if (previousTrimps.length < 7) return null;
  const avg = (a) => a.reduce((x, y) => x + y, 0) / a.length;
  const chronic = avg(previousTrimps.slice(-28));
  if (!(chronic > 0)) return null;
  return avg(previousTrimps.slice(-7)) / chronic;
}
