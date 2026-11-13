// 用我们自己的话复述 noop 在 Apple Watch 路径上的做法（依据 ALGORITHM.md §2 的分析，不是复制 noop 的代码），
// 只用于测试里对照“noop 在同样输入下会得到什么”。

/** noop 缺陷 1：HRV = 自然日内全部 SDNN 的平均（不区分白天和睡眠）。 */
export function dailyAverageSDNN(samples, dayStart) {
  const v = samples.filter((s) => s.start >= dayStart && s.start < dayStart + 86400).map((s) => s.value);
  return v.reduce((a, b) => a + b, 0) / v.length;
}

/** noop 缺陷 3：静息心率 = 5 分钟分箱均值的最小值；箱内样本 ≥ 5 才有资格，没有合格箱时退回所有箱均值的最小值。 */
export function binnedMinRestingHR(points, start, end) {
  const means = []; const qualified = [];
  for (let t = start; t < end; t += 300) {
    const w = points.filter((p) => p.date >= t && p.date < t + 300);
    if (!w.length) continue;
    const m = w.reduce((a, p) => a + p.bpm, 0) / w.length;
    means.push(m);
    if (w.length >= 5 && m >= 25) qualified.push(m);
  }
  return Math.round(qualified.length ? Math.min(...qualified) : Math.min(...means));
}

/** noop 缺陷 4：每个样本的时长 = 前两个样本的时间差，TRIMP = Σ 样本 × 该时长 × 权重。 */
export function firstGapTRIMP(points, perMinute) {
  const dt = Math.abs(points[1].date - points[0].date) / 60;
  return points.reduce((a, p) => a + dt * perMinute(p.bpm), 0);
}

/** noop 缺陷 5：0–100 的负荷量程，100 × ln(TRIMP + 1) / ln(7201)。 */
export const strain100 = (trimp) => (trimp <= 0 ? 0 : (100 * Math.log(trimp + 1)) / Math.log(7201));
