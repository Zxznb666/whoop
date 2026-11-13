// 个人稳健基线（PRD §5.6，代码 Baseline.swift）：第 N 晚之前最近 30 个有效夜的中位数 + 1.4826 × MAD，
// σ 设下限；有效夜不足 30 时向人群先验收缩。只用第 N 晚之前的数据（PRD §5.0 原则 5）。
import { CONFIG, prior } from './config.js';
import { median, mad } from './stats.js';

/**
 * @param values 第 N 晚之前的有效值（按时间升序）
 * @returns {mu, sigma, n, calibrating}；mu 为 null 表示既没有个人数据也没有先验（只有手腕温度会这样）
 */
export function baselineStat(values, metric, profile, year, cfg = CONFIG) {
  const win = values.slice(-cfg.baselineWindow);
  const n = win.length;
  const pMu = median(win);
  const pSigma = cfg.madToSigma * (mad(win) ?? 0);
  const pr = prior(metric, profile, year);
  let mu;
  let sigma;
  if (n >= cfg.baselineWindow) {
    mu = pMu;
    sigma = pSigma;
  } else {
    const k = cfg.priorWeight;
    const personal = pMu ?? 0;
    mu = pr.mu != null ? (k * pr.mu + n * personal) / (k + n) : n === 0 ? null : personal;
    sigma = (k * pr.sigma + n * pSigma) / (k + n);
  }
  return { mu, sigma: Math.max(sigma, cfg.sigmaFloor[metric]), n, calibrating: n < cfg.calibratingBelow };
}

export function zScore(value, stat) {
  if (value == null || stat?.mu == null) return null;
  return (value - stat.mu) / stat.sigma;
}

/** 逐晚累积的观测：每晚记录各指标值与是否有效；有效性可被之后的判断回溯修改（生病排除）。 */
export class BaselineHistory {
  constructor(profile, cfg = CONFIG) {
    this.profile = profile;
    this.cfg = cfg;
    this.obs = [];
  }

  /** 第 index 晚（尚未加入）的基线 */
  stat(metric, year) {
    const values = this.obs.filter((o) => o.valid && o.values[metric] != null).map((o) => o.values[metric]);
    return baselineStat(values, metric, this.profile, year, this.cfg);
  }

  push(values, valid) {
    this.obs.push({ values, valid });
  }

  invalidate(index) {
    if (this.obs[index]) this.obs[index].valid = false;
  }
}
