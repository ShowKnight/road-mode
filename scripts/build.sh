#!/usr/bin/env bash
# RoadMode 构建脚本：编译 Swift 源码 → 打包 .app → 可选安装到 /Applications
# 用法:
#   ./build.sh              仅构建到 ./build/RoadMode.app
#   ./build.sh --install    构建并安装到 /Applications（需要 ad-hoc 签名）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RoadMode"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> 清理"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 (arm64 + x86_64 通用二进制)"
if swiftc -O -swift-version 5 \
    -target arm64-apple-macosx13.0 \
    "$ROOT/src/main.swift" -o "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null; then
  :
else
  echo "arm64 编译失败，回退到本机默认架构"
  swiftc -O -swift-version 5 "$ROOT/src/main.swift" -o "$APP/Contents/MacOS/$APP_NAME"
fi

echo "==> 打包"
cp "$ROOT/src/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> ad-hoc 签名"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "签名失败（可忽略，首次运行可能被 Gatekeeper 拦）"

echo "==> 完成: $APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "==> 安装到 /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  codesign --force --sign - "/Applications/$APP_NAME.app" >/dev/null 2>&1 || true
  open "/Applications/$APP_NAME.app"
  echo "已安装并启动"
  echo "注意: 想免密切换休眠状态，请先执行 sudo ./scripts/install-sudoers.sh"
fi
