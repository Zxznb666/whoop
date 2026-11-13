// 统计工具（代码 Stats/Statistics.swift）。全部为纯函数。

/** 线性插值分位数，等同于 numpy 默认方法；p 取 0…1。 */
export function percentile(values, p) {
  if (!values.length) return null;
  const s = [...values].sort((a, b) => a - b);
  const pos = p * (s.length - 1);
  const lo = Math.floor(pos);
  const hi = Math.min(lo + 1, s.length - 1);
  return s[lo] + (s[hi] - s[lo]) * (pos - lo);
}

export const median = (v) => percentile(v, 0.5);

export function mean(v) {
  return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null;
}

/** 中位数绝对偏差 */
export function mad(v) {
  const m = median(v);
  return m == null ? null : median(v.map((x) => Math.abs(x - m)));
}

export const clamp = (x, lo, hi) => Math.min(Math.max(x, lo), hi);
