// 读取快照（.json 或 .json.gz）与 Vigor 对照结果。
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';

export function readJSON(path) {
  const buf = readFileSync(path);
  return JSON.parse((path.endsWith('.gz') ? gunzipSync(buf) : buf).toString('utf8'));
}

/** 读取 fixtures 目录里的快照：优先 snapshot.json.gz，没有就读 snapshot.json。 */
export function readSnapshot(dir) {
  try {
    return readJSON(`${dir}/snapshot.json.gz`);
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
    return readJSON(`${dir}/snapshot.json`);
  }
}
