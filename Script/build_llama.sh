#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════
# Script/build_llama.sh
# © 2026 Trigin. All rights reserved.
#
# 拉取 llama.cpp 源码并用 cmake + Metal 后端构建静态库。
#   1. 克隆 llama.cpp 到 .deps/llama.cpp（可通过 LLAMA_REF / LLAMA_REPO 覆盖）
#   2. cmake -DLLAMA_METAL=ON 构建 Release
#   3. libtool -static 合并所有 .a → .build/llama/libllama.a
#   4. 覆盖 Sources/Cllama/Include/ 下的占位头文件 + module.modulemap
#
# 幂等：已存在 .deps/llama.cpp 则跳过克隆；已存在 libllama.a 可跳过构建。
# ═════════════════════════════════════════════════════════════════
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEPS_DIR="$ROOT/.deps"
LLAMA_DIR="$DEPS_DIR/llama.cpp"
BUILD_DIR="$ROOT/.build/llama-build"
OUT_DIR="$ROOT/.build/llama"
INC_DIR="$ROOT/Sources/Cllama/Include"
MM_DIR="$ROOT/Sources/Cllama"

LLAMA_REPO="${LLAMA_REPO:-https://github.com/ggml-org/llama.cpp}"
LLAMA_REF="${LLAMA_REF:-master}"   # 如需锁版本，改成具体 tag，例如 b4027

echo "▶ LocalCoder IDE · build_llama.sh  © 2026 Trigin"
echo "  • repo : $LLAMA_REPO"
echo "  • ref  : $LLAMA_REF"
echo "  • metal: ON"

# 1. 克隆
if [ ! -d "$LLAMA_DIR/.git" ]; then
    echo "⏳ 克隆 llama.cpp …"
    mkdir -p "$DEPS_DIR"
    rm -rf "$LLAMA_DIR"
    git clone --depth 1 --branch "$LLAMA_REF" "$LLAMA_REPO" "$LLAMA_DIR"
else
    echo "✓ llama.cpp 已存在 ($LLAMA_DIR)"
fi

# 2. 配置 + 构建
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR" "$INC_DIR"

echo "⏳ cmake 配置 …"
cmake -S "$LLAMA_DIR" -B "$BUILD_DIR" \
    -DLLAMA_METAL=ON \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" || {
        # Metal 在 Linux / Rosetta 上可能失败；降级到 CPU-only
        echo "⚠️ Metal 配置失败，降级 CPU-only …"
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
        cmake -S "$LLAMA_DIR" -B "$BUILD_DIR" \
            -DLLAMA_METAL=OFF \
            -DLLAMA_BUILD_EXAMPLES=OFF \
            -DLLAMA_BUILD_TESTS=OFF \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
    }

echo "⏳ 编译 $(sysctl -n hw.ncpu 2>/dev/null || echo 4) 核 …"
cmake --build "$BUILD_DIR" --config Release -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# 3. 合并静态库
echo "⏳ 合并 .a → $OUT_DIR/libllama.a"
cd "$BUILD_DIR"
LIBS=()
while IFS= read -r f; do LIBS+=("$f"); done < <(find . -name '*.a' -type f | sort)

if [ ${#LIBS[@]} -eq 0 ]; then
    echo "❌ 未找到 .a 产物，构建失败"
    exit 1
fi

if command -v libtool >/dev/null 2>&1; then
    libtool -static -o "$OUT_DIR/libllama.a" "${LIBS[@]}"
else
    cp "$(find . -name 'libllama.a' | head -1)" "$OUT_DIR/libllama.a"
fi

# 4. 覆盖头文件
echo "⏳ 拷贝头文件 → $INC_DIR"
# 清理旧的占位头
rm -f "$INC_DIR"/*.h

cp "$LLAMA_DIR/include/llama.h" "$INC_DIR/llama.h" || {
    # 某些版本头路径在 src/
    src="$(find "$LLAMA_DIR" -maxdepth 3 -name 'llama.h' -type f | head -1)"
    cp "$src" "$INC_DIR/llama.h"
}

# ggml headers（llama.h 内部会 include）
for sub in ggml/include src; do
    d="$LLAMA_DIR/$sub"
    [ -d "$d" ] || continue
    for h in "$d"/ggml*.h; do
        [ -f "$h" ] && cp "$h" "$INC_DIR/" || true
    done
done

# modulemap 覆盖（真实 llama.h 可能是 C++ header，保留我们的简单 modulemap 即可）
cat > "$MM_DIR/module.modulemap" <<'MM'
framework module Cllama {
    umbrella header "llama.h"
    header "llama.h"
    header "ggml.h"
    header "ggml-cpu.h"
    header "ggml-metal.h"
    header "ggml-alloc.h"
    header "ggml-backend.h"
    header "ggml-quants.h"
    export *
    link "llama"
}
MM

echo "✅ 完成：$(du -h "$OUT_DIR/libllama.a" | awk '{print $1}')"
