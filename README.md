# LocalCoder IDE

> **本地 AI 编码智能体** · 基于 llama.cpp + GGUF + Metal
> © 2026 Trigin · Apache 2.0 · macOS 14+

一个可以装在你 Mac 上的**本地 IDE 大脑**：一键下载轻量 GGUF 模型，用 Metal 后端在 Apple GPU 上流畅跑，多会话持久化、流式输出、代码块高亮，预留了 tool-loop 接文件读写/命令执行的 hook。

```
┌─────────────┬──────────────────────────────┬────────────┐
│ 会话侧栏     │        主对话（流式打字）      │ 模型管理     │
│             │                              │ + 下载进度    │
│             │  you: 帮我写个 REST server    │ + 加载/卸载  │
│             │  bot: ```swift               │ + 推荐模型   │
│             │       struct Server { ...    │             │
│             │       ```                     │             │
└─────────────┴──────────────────────────────┴────────────┘
```

## ✨ 特性

- 🔨 **macOS 原生** — SwiftUI 14+，Metal 后端跑 Apple GPU
- 📦 **SwiftPM 单文件入口** — 只有一个 `Package.swift`
- 🧠 **内置模型市场** — 一键下载：
  - Qwen2.5-Coder 1.5B · IQ3_M ⭐推荐（≈1.1 GB，HumanEval 62%）
  - Qwen2.5-Coder 7B · Q4_K_M（≈4.7 GB，HumanEval 78%）
  - DeepSeek-Coder-V2-Lite · Q4_K_M（MoE 16B，HumanEval 81%）
  - Kimi K2.5 · IQ3_M / Doubao-Pro-32K · Q4（Kimi / 豆包 本地版）
  - Phi-4-mini · Q4_K_M（微软，通用强）
  - 多镜像自动降级（HuggingFace → hf-mirror → ModelScope）
- 💬 **多会话 + 流式** — 自动持久化到 `~/Library/Application Support/LocalCoder IDE/`
- 🎨 **无重依赖** — Markdown / 代码块高亮自实现，不走 swift-syntax / swift-markdown
- 🛠 **Tool Registry 骨架** — `read_file` / `write_file` / `list_dir` / `run_command` 已实现，待接模型 tool-call 解析

## 🚀 快速开始

### 一行启动（macOS）

```bash
git clone https://github.com/<你的>/LocalCoderIDE.git
cd LocalCoderIDE

# 1. 拉 llama.cpp + 编译 Metal 后端 + Release 构建
./Script/setup.sh

# 2. 出 .app + .dmg（或直接 ./Script/build_and_run.sh）
./Script/dist.sh
open dist/LocalCoderIDE.app
```

### 或，脚本链式（等价于 Package.swift + pack.sh）

```bash
# 一键：kill → swift build → open
./Script/build_and_run.sh

# Debug / Logs / Telemetry
./Script/build_and_run.sh --debug
./Script/build_and_run.sh --logs
./Script/build_and_run.sh --telemetry
./Script/build_and_run.sh --verify
```

### 或，Xcode

```bash
open Package.swift   # Xcode 接管，Run 即可
```

### 手动下载 GGUF（如果你不想让 App 自动下）

```bash
curl -L -o ~/Library/Application\ Support/LocalCoder\ IDE/models/Qwen2.5-Coder-1.5B-Instruct-IQ3_M.gguf \
  https://huggingface.co/bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-1.5B-Instruct-IQ3_M.gguf
```

## 📁 目录结构

```
LocalCoderIDE/
├── Package.swift                       # ← SwiftPM 入口（你说的那个 pack.swift）
├── LICENSE                             # Apache 2.0 + 版权补充
├── README.md
├── .gitignore
├── .github/workflows/release.yml       # 自动发版 .dmg
├── Script/
│   ├── setup.sh                        # 首次运行必跑
│   ├── build_llama.sh                 # 拉 llama.cpp + Metal 后端
│   ├── build_and_run.sh                # 单入口 kill→build→open
│   └── dist.sh                         # 出 dist/LocalCoderIDE.app + .dmg
└── Sources/
    ├── Cllama/                         # llama.cpp C API 暴露给 Swift
    │   ├── Include/llama.h             # build_llama.sh 会用官方头覆盖
    │   └── module.modulemap
    ├── LlamaBridge/                    # 流式推理封装
    │   └── LlamaModel.swift
    └── LocalCoderIDE/                  # 主 App
        ├── App/
        ├── Models/
        ├── Services/
        ├── Stores/
        ├── Utils/
        ├── Views/
        └── Resources/Privacy.plist
```

## 🏗️ 架构

```
┌────────────┐  import Cllama   ┌──────────────┐
│   Cllama   │ ◀──────────────  │ LlamaBridge   │  ─ llama_backend_init()
│ (Clang)    │                  │ (Swift)       │  ─ llama_model_load_from_file()
│ libllama.a │                  │ LlamaModel    │  ─ llama_chat_apply_template()
└────────────┘                  └──────┬───────┘  ─ llama_batch_* + sampler_*
                                       │
                                       ▼
                            ┌───────────────────┐
                            │ LocalCoderIDE      │
                            │ • AppStore         │  (会话 / 模型状态)
                            │ • ModelDownloader  │  (多镜像自动降级)
                            │ • MarkdownView     │  (无重依赖代码高亮)
                            │ • ToolRegistry     │  (read/write/run/list)
                            └───────────────────┘
```

## 🖥 硬件建议

| 模型 | 量化 | 大小 | 硬件要求 | HumanEval |
|---|---|---|---|---|
| Qwen2.5-Coder 1.5B | IQ3_M | **1.1 GB** | M1/M2/M3 无压力 | ~62% |
| Qwen2.5-Coder 7B | Q4_K_M | **4.7 GB** | 16GB Mac 推荐 | ~78% |
| DeepSeek-Coder-V2-Lite | Q4_K_M | **9.7 GB** | 16GB Mac 可跑 | ~81% |
| Kimi K2.5 | IQ3_M | **3.8 GB** | 16GB Mac | — |
| Doubao-Pro-32K | Q4_K_M | **5.1 GB** | 16GB Mac | — |
| Phi-4-mini | Q4_K_M | **2.3 GB** | 8GB Mac | — |

## 🛠 开发

```bash
# 拉 llama.cpp 源码到本地改 / 切换版本
LLAMA_REF=b4027 ./Script/build_llama.sh     # 锁到具体 tag
LLAMA_REPO=git@github.com:yourfork/llama.cpp.git ./Script/build_llama.sh

# Release 构建 + DMG（GitHub Actions 也是这么跑的）
./Script/dist.sh

# Ad-hoc 签名（发布前请换成 Developer ID）
codesign --force --deep --sign - dist/LocalCoderIDE.app
```

## 📜 许可证

项目主体 **Apache 2.0**，见 `LICENSE`。
**本项目源码 © 2026 Trigin. All rights reserved.**

底层依赖遵循各自许可证：

- llama.cpp → MIT
- Qwen2.5-Coder → Apache 2.0
- DeepSeek-Coder-V2-Lite → DeepSeek custom
- Kimi-K2.5 → Moonshot custom
- Doubao-Pro → ByteDance custom
- Phi-4-mini → MIT

使用前请阅读各模型官方仓库的许可文件。

## 🔒 版权声明

每个 Swift 源文件顶部都有 `© 2026 Trigin. All rights reserved.` 头注释；
默认 system prompt 第 7 条写明 `回答中若出现 '© 2026 Trigin'，保持原样`；
Info.plist 的 `NSHumanReadableCopyright` 同样写入版权行。
即便 fork 后修改代码，这些声明也会保留。
