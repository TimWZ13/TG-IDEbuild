#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════
# Script/build_and_run.sh
# © 2026 Trigin. All rights reserved.
#
# macOS 上 LocalCoder IDE 的单入口 kill→build→open。
# 可选：
#   --debug     lldb attach
#   --logs      stream unified log
#   --telemetry 仅 stream subsystem=com.trigin.LocalCoderIDE
#   --verify    启动后 pgrep 验证
# ═════════════════════════════════════════════════════════════════
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="LocalCoderIDE"
BUNDLE_ID="com.trigin.LocalCoderIDE"
DIST="$ROOT/dist"

MODE="run"
for a in "$@"; do case "$a" in
    --debug)     MODE="debug" ;;
    --logs)      MODE="logs" ;;
    --telemetry) MODE="telemetry" ;;
    --verify)    MODE="verify" ;;
    *) echo "未知参数: $a"; exit 1 ;;
esac; done

[ "$(uname)" = "Darwin" ] || { echo "❌ 只能在 macOS 上运行 build_and_run.sh"; exit 1; }

# 0. 确保 llama 静态库已构建
if [ ! -f "$ROOT/.build/llama/libllama.a" ]; then
    echo "⚠️  未检测到 libllama.a，先调用 setup.sh …"
    bash "$ROOT/Script/setup.sh" --skip-llama 2>/dev/null || bash "$ROOT/Script/setup.sh"
fi

# 1. kill 旧进程
echo "▶ kill 旧进程 …"
pkill -x "$APP_NAME" 2>/dev/null || true
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
sleep 0.5

# 2. Release 构建
echo "▶ swift build -c release …"
swift build -c release

BIN="$ROOT/.build/release/$APP_NAME"
[ -x "$BIN" ] || { echo "❌ 可执行文件不存在: $BIN"; exit 1; }

# 3. 组装 .app bundle
APP="$DIST/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

# Info.plist
plutil -convert binary1 -o "$APP/Contents/Info.plist" - <<PLIST 2>/dev/null || cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>LocalCoder IDE</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Trigin. All rights reserved.</string>
</dict></plist>
PLIST

# Privacy.plist
if [ -f "$ROOT/Sources/LocalCoderIDE/Resources/Privacy.plist" ]; then
    cp "$ROOT/Sources/LocalCoderIDE/Resources/Privacy.plist" "$APP/Contents/Resources/"
fi

# 4. 启动
echo "▶ 启动 $APP_NAME …"
case "$MODE" in
    run)
        /usr/bin/open -n "$APP" ;;
    debug)
        /usr/bin/open -n "$APP"; sleep 1
        lldb -p "$(pgrep -x "$APP_NAME" | head -1)" ;;
    logs)
        /usr/bin/open -n "$APP"; sleep 1
        /usr/bin/log stream --info --debug --style compact \
            --predicate "(process == \"$APP_NAME\")" ;;
    telemetry)
        /usr/bin/open -n "$APP"; sleep 1
        /usr/bin/log stream --info --debug --style compact \
            --predicate "(subsystem == \"$BUNDLE_ID\")" ;;
    verify)
        /usr/bin/open -n "$APP"; sleep 1.5
        if pgrep -x "$APP_NAME" >/dev/null; then
            echo "✅ $APP_NAME 运行中 (PID=$(pgrep -x "$APP_NAME"))"
        else
            echo "❌ 进程未启动"; exit 1
        fi ;;
esac
