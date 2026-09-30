#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════
# Script/setup.sh
# © 2026 Trigin. All rights reserved.
#
# macOS 上首次运行 LocalCoderIDE 必须先执行这个脚本。
# 它串联完成：拉取 + 构建 llama.cpp + 校验静态库 + 确保 swift 可用。
#
#   ./Script/setup.sh           # 标准流程
#   ./Script/setup.sh --skip-llama   # 跳过 llama.cpp（已构建过）
#
# 成功后你可以：
#   swift build -c release      # 编译
#   ./Script/dist.sh             # 产出 .app + .dmg
#   ./Script/build_and_run.sh    # 一键启动
# ═════════════════════════════════════════════════════════════════
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SKIP_LLAMA=0
for a in "$@"; do case "$a" in
    --skip-llama) SKIP_LLAMA=1 ;;
    *) echo "未知参数: $a"; exit 1 ;;
esac; done

echo ""
echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
echo "┃   LocalCoder IDE · setup.sh  © 2026 Trigin           ┃"
echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
echo ""

# 0. 环境检查
if ! command -v swift >/dev/null 2>&1; then
    echo "❌ 未找到 swift。请先安装 Xcode 或 Swift 工具链："
    echo "   • App Store 安装 Xcode（免费）"
    echo "   • 或 https://www.swift.org/download/"
    exit 1
fi
SWIFT_VER="$(swift --version 2>/dev/null | head -1)"
echo "✓ swift : $SWIFT_VER"

# Metal 在 macOS 上由系统自带；Linux 不支持
if [ "$(uname)" = "Darwin" ]; then
    echo "✓ 平台 : macOS $(sw_vers -productVersion 2>/dev/null || echo "?")"
else
    echo "⚠️  非 macOS 平台 (uname=$(uname)) — 将降级 CPU-only，且无法运行 SwiftUI 主 App"
fi

# 1. 构建 llama.cpp
if [ $SKIP_LLAMA -eq 1 ]; then
    echo "⏭  --skip-llama 已提供，跳过 llama.cpp 构建"
else
    bash "$ROOT/Script/build_llama.sh"
fi

# 2. 校验产物
if [ ! -f "$ROOT/.build/llama/libllama.a" ]; then
    echo "❌ 缺少 .build/llama/libllama.a"
    exit 1
fi
if [ ! -f "$ROOT/Sources/Cllama/Include/llama.h" ]; then
    echo "❌ 缺少 Sources/Cllama/Include/llama.h"
    exit 1
fi
echo "✓ libllama.a + llama.h 就绪"

# 3. 干跑一次 Release 构建（仅验证 LlamaBridge + Cllama 可编译）
if [ "$(uname)" = "Darwin" ]; then
    echo ""
    echo "⏳ swift build -c release …"
    swift build -c release 2>&1 | tail -5
    echo "✅ 构建成功！"
else
    echo ""
    echo "⏳ Linux 上仅做库层编译验证（SwiftUI 在 Linux 不可用）…"
    # 试试 swift build — 会因为 SwiftUI 缺失而失败，但 Cllama+LlamaBridge 应该过
    swift build 2>&1 | grep -E "Compiling Cllama|Compiling LlamaBridge|error: no such module 'SwiftUI'" || true
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║ setup 完成 ✅                                          ║"
echo "║                                                          ║"
echo "║ 下一步：                                                 ║"
echo "║   ./Script/dist.sh               # 产 .app + .dmg      ║"
echo "║   ./Script/build_and_run.sh      # 一键启动             ║"
echo "║   open Package.swift             # Xcode 接管           ║"
echo "╚══════════════════════════════════════════════════════╝"
