// swift-tools-version:5.10
// ═══════════════════════════════════════════════════════════════════
// TG IDE · Package.swift
// © 2026 Trigin. All rights reserved.
// Version: 0.3.0
//
// 本地 AI 编码智能体，基于 llama.cpp + GGUF + Metal。
//
// 快速开始（macOS）：
//   ./build.sh                      # 一键编译并产出 dist/TGIDE.app
//   或在 Xcode 中 Open → Package.swift → Cmd+B
// ═══════════════════════════════════════════════════════════════════

import PackageDescription

let package = Package(
    name: "TGIDE",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TGIDE", targets: ["TGIDE"])
    ],
    targets: [
        // ─ 1. Cllama：暴露 llama.cpp C API 给 Swift（Clang target）
        //    build.sh 会把 llama.cpp 官方头文件覆盖到 Include/
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

        // ─ 3. TGIDE：主 App（SwiftUI）
        .executableTarget(
            name: "TGIDE",
            dependencies: ["LlamaBridge"],
            path: "Sources/TGIDE",
            exclude: ["Resources/Info.plist"],
            resources: [
                .copy("Resources/Privacy.plist"),
                .copy("Resources/AppIcon.appiconset")
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
