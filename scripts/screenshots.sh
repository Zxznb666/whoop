#!/usr/bin/env bash
# 截图脚本（施工文档 §5 阶段 6 第 6 条）：构建 → 安装 → 逐个路由启动 → 浅色与深色截图。
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="com.example.vigor"
DERIVED="build/screenshots"
OUT="docs/screenshots"
ROUTES=(summary recovery sleep strain workout journal browse metric:hrv metric:rhr settings lab lab:night report coach diagnostics onboarding)

UDID="$(xcrun simctl list devices available | grep "iPhone 17 Pro (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
if [[ -z "$UDID" ]]; then
  echo "找不到 iPhone 17 Pro 模拟器" >&2
  exit 1
fi

xcodegen generate >/dev/null
xcodebuild -project Vigor.xcodeproj -scheme Vigor -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build -quiet

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Vigor.app"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"

mkdir -p "$OUT"
for mode in light dark; do
  xcrun simctl ui "$UDID" appearance "$mode"
  for route in "${ROUTES[@]}"; do
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -VigorRoute "$route" >/dev/null
    sleep 4
    name="${route//:/-}"
    xcrun simctl io "$UDID" screenshot "$OUT/${name}-${mode}.png" >/dev/null
    echo "已截图：$OUT/${name}-${mode}.png"
  done
done
xcrun simctl ui "$UDID" appearance light
