#!/bin/bash
# 打包供“全能签”重签名的 IPA：Release 构建不签名，再由内到外 ad-hoc 签名并嵌入各自的 entitlements。
# 用法：scripts/package-ipa.sh            输出 dist/Vigor-<版本号>.ipa
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
xcodebuild -project Vigor.xcodeproj -scheme Vigor -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/ipa \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build -quiet

rm -rf build/Payload && mkdir -p build/Payload dist
cp -R build/ipa/Build/Products/Release-iphoneos/Vigor.app build/Payload/
APP=build/Payload/Vigor.app

# 由内到外：嵌入的 framework / dylib → 手表小组件 → 手表 App → iOS 小组件 → 主 App
find "$APP" -depth \( -name "*.framework" -o -name "*.dylib" \) -exec codesign -f -s - {} \;
sign() { [ -d "$1" ] && codesign -f -s - --entitlements "$2" "$1"; }
sign "$APP/Watch/VigorWatch.app/PlugIns/VigorWatchWidgets.appex" WatchWidgets/VigorWatchWidgets.entitlements || true
sign "$APP/Watch/VigorWatch.app" Watch/VigorWatch.entitlements || true
sign "$APP/PlugIns/VigorWidgets.appex" Widgets/VigorWidgets.entitlements || true
codesign -f -s - --entitlements App/Vigor.entitlements "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
(cd build && rm -f "../dist/Vigor-$VERSION.ipa" && zip -qry "../dist/Vigor-$VERSION.ipa" Payload)
codesign -d --entitlements - "$APP" 2>&1 | grep -q "com.apple.developer.healthkit" || { echo "主 App 缺少 HealthKit 权限" >&2; exit 1; }
echo "dist/Vigor-$VERSION.ipa"
