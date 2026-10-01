// swift-tools-version:5.10
// ═══════════════════════════════════════════════════════════════════
// LocalCoder IDE · Package.swift
// © 2026 Trigin. All rights reserved.
// Version: 0.2.0
//
// 本地 AI 编码智能体，基于 llama.cpp + GGUF + Metal。
//
// 快速开始（macOS）：
//   ./Script/setup.sh            # 构建 llama.cpp 静态库 + .dSYM
//   swift build -c release       # 编译
//   ./Script/dist.sh             # 产出 dist/LocalCoderIDE.app 及 .dmg
//
// 或：
//   ./Script/build_and_run.sh    # 一键 kill→build→open
// ═══════════════════════════════════════════════════════════════════

import PackageDescription

let package = Package(
    name: "LocalCoderIDE",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LocalCoderIDE", targets: ["LocalCoderIDE"])
    ],
    targets: [
        // ─ 1. Cllama：暴露 llama.cpp C API 给 Swift（Clang target）
        //    build_llama.sh 会把 llama.cpp 官方头文件覆盖到 Include/
        //    静态库 libllama.a 放到 .build/llama/
        .target(
            name: "Cllama",
            path: "Sources/Cllama",
            publicHeadersPath: "Include",
            linkerSettings: [
                .linkedLibrary("llama"),
                .unsafeFlags(["-L", ".build/llama"])
            ]
        ),

        // ─ 2. LlamaBridge：Swift 封装（流式 token 推理）
        .target(
            name: "LlamaBridge",
            dependencies: ["Cllama"],
            path: "Sources/LlamaBridge"
        ),

        // ─ 3. LocalCoderIDE：主 App（SwiftUI）
        .executableTarget(
            name: "LocalCoderIDE",
            dependencies: ["LlamaBridge"],
            path: "Sources/LocalCoderIDE",
            resources: [
                .copy("Resources/Privacy.plist")
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
