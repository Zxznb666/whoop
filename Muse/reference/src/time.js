// 本地时间工具：所有时间戳都是 Unix 秒（UTC），本地时间按固定偏移换算（M-01）。
import { CONFIG } from './config.js';

const off = (cfg) => (cfg?.tzOffsetMinutes ?? CONFIG.tzOffsetMinutes) * 60;

function parts(t, cfg) {
  const d = new Date((t + off(cfg)) * 1000);
  return { y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate(), h: d.getUTCHours(), min: d.getUTCMinutes() };
}

const pad = (n) => String(n).padStart(2, '0');

/** 本地日期键 YYYY-MM-DD */
export function dayKey(t, cfg) {
  const p = parts(t, cfg);
  return `${p.y}-${pad(p.m)}-${pad(p.d)}`;
}

export const localHour = (t, cfg) => parts(t, cfg).h;

/** 一天中的分钟数（0–1439） */
export function minuteOfDay(t, cfg) {
  const p = parts(t, cfg);
  return p.h * 60 + p.min;
}

/** HH:MM */
export function hhmm(t, cfg) {
  const p = parts(t, cfg);
  return `${pad(p.h)}:${pad(p.min)}`;
}

/** 本地日期键当天 00:00 的 Unix 秒 */
export function startOfDayKey(key, cfg) {
  const [y, m, d] = key.split('-').map(Number);
  return Date.UTC(y, m - 1, d) / 1000 - off(cfg);
}

export function localYear(t, cfg) {
  return parts(t, cfg).y;
}
