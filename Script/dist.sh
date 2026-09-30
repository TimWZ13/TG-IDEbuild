#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════
# Script/dist.sh
# © 2026 Trigin. All rights reserved.
#
# 把 LocalCoder IDE 打造成可拖拽的 dist/ 目录：
#   dist/LocalCoderIDE.app        — 应用本体
#   dist/LocalCoderIDE.dmg        — DMG（macOS 上自动生成）
#
# 用法：
#   cd LocalCoderIDE && ./Script/dist.sh
#
# 前置：./Script/setup.sh 已跑过，libllama.a 已存在。
# 本脚本等价于 Package.swift + dist.sh 的组合 —— 这就是你说的
# "pack.swift" 那个"cd 进文件夹就能出 .app"的入口。
# ═════════════════════════════════════════════════════════════════
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="LocalCoderIDE"
BUNDLE_ID="com.trigin.LocalCoderIDE"
VERSION="${VERSION:-0.2.0}"
BUILD="${BUILD:-$(date +%Y%m%d%H%M%S)}"
DIST="$ROOT/dist"
STAGE="$DIST/_stage"

[ "$(uname)" = "Darwin" ] || { echo "❌ dist.sh 只能在 macOS 上运行"; exit 1; }

# 0. 确保依赖就绪
[ -f "$ROOT/.build/llama/libllama.a" ] || {
    echo "⏳ 先 setup …"; bash "$ROOT/Script/setup.sh";
}

# 1. Release 构建
echo "▶ swift build -c release …"
swift build -c release
BIN="$ROOT/.build/release/$APP_NAME"
[ -x "$BIN" ] || { echo "❌ BIN 未生成"; exit 1; }

# 2. 清理 + 组装 .app
echo "▶ 组装 $APP_NAME.app …"
rm -rf "$DIST/$APP_NAME.app" "$STAGE"
mkdir -p "$DIST/$APP_NAME.app/Contents/MacOS" \
         "$DIST/$APP_NAME.app/Contents/Resources" \
         "$STAGE"

cp "$BIN" "$DIST/$APP_NAME.app/Contents/MacOS/$APP_NAME"
chmod +x "$DIST/$APP_NAME.app/Contents/MacOS/$APP_NAME"

# Info.plist（用 PlistBuddy 更兼容；兜底 XML）
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" \
                        -c "Add :CFBundleDisplayName string LocalCoder\ IDE" \
                        -c "Add :CFBundleIdentifier string $BUNDLE_ID" \
                        -c "Add :CFBundleVersion string 1" \
                        -c "Add :CFBundleShortVersionString string $VERSION" \
                        -c "Add :CFBundlePackageType string APPL" \
                        -c "Add :CFBundleExecutable string $APP_NAME" \
                        -c "Add :LSMinimumSystemVersion string 14.0" \
                        -c "Add :NSPrincipalClass string NSApplication" \
                        -c "Add :NSHighResolutionCapable bool true" \
                        -c "Add :NSHumanReadableCopyright string ©\ 2026\ Trigin.\ All\ rights\ reserved." \
                        -c "Add :NSRequiresAquaSystemAppearance bool false" \
                        -c "Add :NSSupportsAutomaticTermination bool false" \
                        "$DIST/$APP_NAME.app/Contents/Info.plist" 2>/dev/null || {
    cat > "$DIST/$APP_NAME.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>LocalCoder IDE</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Trigin. All rights reserved.</string>
</dict></plist>
PLIST
}

# Privacy.plist
[ -f "$ROOT/Sources/LocalCoderIDE/Resources/Privacy.plist" ] && \
    cp "$ROOT/Sources/LocalCoderIDE/Resources/Privacy.plist" \
       "$DIST/$APP_NAME.app/Contents/Resources/"

# Frameworks: Metal / MetalKit / AppKit / SwiftUI 都是系统库，不需要复制
# dSYM（方便崩溃符号化）
if [ -f "$BIN.dSYM" ]; then
    cp -R "$BIN.dSYM" "$DIST/$APP_NAME.app/Contents/" 2>/dev/null || true
fi

# 签名（临时 ad-hoc；发布时请用 Developer ID）
codesign --force --deep --sign - "$DIST/$APP_NAME.app" 2>/dev/null || true

echo "✅ $DIST/$APP_NAME.app ($(du -sh "$DIST/$APP_NAME.app" | cut -f1))"

# 3. DMG
echo "▶ 生成 $APP_NAME.dmg …"
DMG="$DIST/$APP_NAME.dmg"
rm -f "$DMG"

# 创建 stage 目录: .app + Applications 别名
cp -R "$DIST/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# hdiutil 用 UDZO（压缩），文件系统 APFS
hdiutil create \
    -volname "LocalCoder IDE $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" | tail -2

rm -rf "$STAGE"
echo "✅ $DMG"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║ dist.sh 完成 ✅                                        ║"
echo "║                                                          ║"
echo "║   $DIST/$APP_NAME.app                                  ║"
echo "║   $DIST/$APP_NAME.dmg                                  ║"
echo "║                                                          ║"
echo "║ 直接双击 .dmg 即可拖到 Applications。                   ║"
echo "║  ad-hoc 签名；发布前请用 Developer ID 重新签名公证。     ║"
echo "╚══════════════════════════════════════════════════════╝"
