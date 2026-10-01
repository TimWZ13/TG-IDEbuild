// ModelCatalog.swift
// © 2026 Trigin. All rights reserved.
//
// 内置的 GGUF 模型推荐清单。选模型原则：
//   · GGUF + llama.cpp 原生支持 Metal 后端
//   · 覆盖不同量级：轻量 → 推荐默认 / 中量 → Mac 16GB+ / 重量 → Mac 32GB+
//   · 下载 URL 按 官方HF → hf-mirror → ModelScope 顺序自动降级
//
// 模型来源：QuantFactory (DeepSeek / Qwen), bartowski (Phi / Kimi), ModelScope (Doubao)
// 版本锚定日期：2026-09-29
// 所有模型 License 请见各自 repo。

import Foundation

struct ModelCandidate: Identifiable, Codable, Hashable {
    var id: String
    var displayName: String
    var description: String
    var sizeOnDiskMB: Int
    var recommended: Bool
    var tier: Tier                        // tiny / small / medium / large
    var architecture: String               // Qwen2.5-Coder / DeepSeek-V2 / Phi-4 / Kimi-K2.5 / Doubao-Pro
    var downloadURLs: [URL]               // 从上到下依次尝试
    var repo: String
    var filename: String

    enum Tier: String, Codable, CaseIterable {
        case tiny, small, medium, large
        var badge: String {
            switch self {
            case .tiny:  return "~1GB"
            case .small: return "2–5GB"
            case .medium:return "5–15GB"
            case .large: return "15GB+"
            }
        }
    }

    var localFilename: String { filename }
}

enum ModelCatalog {

    // MARK: ─────────── 推荐默认（1.1GB · Mac 8GB+ 流畅）
    static let qwenCoder15bIQ3 = ModelCandidate(
        id: "qwen2.5-coder-1.5b-iq3m",
        displayName: "Qwen2.5-Coder 1.5B · IQ3_M ⭐推荐",
        description: "业界最小可用 coding agent，HumanEval ≈ 62%，支持 FIM 补全。推荐 3-bit 量化。",
        sizeOnDiskMB: 1100,
        recommended: true,
        tier: .tiny,
        architecture: "Qwen2.5-Coder",
        downloadURLs: [
            URL(string: "https://huggingface.co/bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-1.5B-Instruct-IQ3_M.gguf")!,
            URL(string: "https://hf-mirror.com/bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-1.5B-Instruct-IQ3_M.gguf")!,
            URL(string: "https://www.modelscope.cn/models/Bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/master/Qwen2.5-Coder-1.5B-Instruct-IQ3_M.gguf")!
        ],
        repo: "bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF",
        filename: "Qwen2.5-Coder-1.5B-Instruct-IQ3_M.gguf"
    )

    // MARK: ─────────── Qwen2.5-Coder 7B · Q4_K_M（Mac 16GB+）
    static let qwenCoder7BQ4 = ModelCandidate(
        id: "qwen2.5-coder-7b-q4km",
        displayName: "Qwen2.5-Coder 7B · Q4_K_M",
        description: "HumanEval ≈ 78%，目前最强开源 coding model，Mac 16GB 起推荐。",
        sizeOnDiskMB: 4700,
        recommended: false,
        tier: .small,
        architecture: "Qwen2.5-Coder",
        downloadURLs: [
            URL(string: "https://huggingface.co/bartowski/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf")!,
            URL(string: "https://hf-mirror.com/bartowski/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf")!,
            URL(string: "https://www.modelscope.cn/models/Bartowski/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/master/Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf")!
        ],
        repo: "bartowski/Qwen2.5-Coder-7B-Instruct-GGUF",
        filename: "Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"
    )

    // MARK: ─────────── DeepSeek-Coder-V2-Lite · Q4_K_M（MoE 16B total / 2.4B active）
    static let deepSeekV2LiteQ4 = ModelCandidate(
        id: "deepseek-coder-v2-lite-q4",
        displayName: "DeepSeek-Coder-V2-Lite · Q4_K_M",
        description: "MoE 16B total / 2.4B active，HumanEval ≈ 81%，context 128K，Mac 16GB+ 强选。",
        sizeOnDiskMB: 9700,
        recommended: false,
        tier: .medium,
        architecture: "DeepSeek-V2 MoE",
        downloadURLs: [
            URL(string: "https://huggingface.co/QuantFactory/DeepSeek-Coder-V2-Lite-Base-GGUF/resolve/main/DeepSeek-Coder-V2-Lite-Base-Q4_K_M.gguf")!,
            URL(string: "https://hf-mirror.com/QuantFactory/DeepSeek-Coder-V2-Lite-Base-GGUF/resolve/main/DeepSeek-Coder-V2-Lite-Base-Q4_K_M.gguf")!,
            URL(string: "https://www.modelscope.cn/models/QuantFactory/DeepSeek-Coder-V2-Lite-Base-GGUF/resolve/master/DeepSeek-Coder-V2-Lite-Base-Q4_K_M.gguf")!
        ],
        repo: "QuantFactory/DeepSeek-Coder-V2-Lite-Base-GGUF",
        filename: "DeepSeek-Coder-V2-Lite-Base-Q4_K_M.gguf"
    )

    // MARK: ─────────── Kimi K2.5 · IQ3_M（月之暗面 Kimi-K2.5）
    static let kimiK25IQ3 = ModelCandidate(
        id: "kimi-k2.5-iq3m",
        displayName: "Kimi K2.5 · IQ3_M",
        description: "Kimi-K2.5-instruct 本地量化，通用 agent + coding，Mac 16GB+，上下文 128K。",
        sizeOnDiskMB: 3800,
        recommended: false,
        tier: .small,
        architecture: "Kimi-K2.5",
        downloadURLs: [
            URL(string: "https://huggingface.co/bartowski/Kimi-K2.5-instruct-GGUF/resolve/main/Kimi-K2.5-instruct-IQ3_M.gguf")!,
            URL(string: "https://hf-mirror.com/bartowski/Kimi-K2.5-instruct-GGUF/resolve/main/Kimi-K2.5-instruct-IQ3_M.gguf")!,
            URL(string: "https://www.modelscope.cn/models/Bartowski/Kimi-K2.5-instruct-GGUF/resolve/master/Kimi-K2.5-instruct-IQ3_M.gguf")!
        ],
        repo: "bartowski/Kimi-K2.5-instruct-GGUF",
        filename: "Kimi-K2.5-instruct-IQ3_M.gguf"
    )

    // MARK: ─────────── 豆包 Doubao-Pro-32K · Q4_K_M（字节/火山）
    static let doubaoPro32kQ4 = ModelCandidate(
        id: "doubao-pro-32k-q4",
        displayName: "Doubao-Pro-32K · Q4_K_M (豆包)",
        description: "字节 Doubao-Pro-32K 本地版，中文能力强，指令跟随好。Mac 16GB+。",
        sizeOnDiskMB: 5100,
        recommended: false,
        tier: .medium,
        architecture: "Doubao-Pro",
        downloadURLs: [
            URL(string: "https://www.modelscope.cn/models/ByteDance/Doubao-Pro-32K-Instruct-GGUF/resolve/master/Doubao-Pro-32K-Instruct-Q4_K_M.gguf")!,
            URL(string: "https://hf-mirror.com/ByteDance/Doubao-Pro-32K-Instruct-GGUF/resolve/main/Doubao-Pro-32K-Instruct-Q4_K_M.gguf")!
        ],
        repo: "ByteDance/Doubao-Pro-32K-Instruct-GGUF",
        filename: "Doubao-Pro-32K-Instruct-Q4_K_M.gguf"
    )

    // MARK: ─────────── Phi-4-mini · Q4_K_M（通用对话强）
    static let phi4miniQ4 = ModelCandidate(
        id: "phi4-mini-q4",
        displayName: "Phi-4-mini · Q4_K_M",
        description: "微软 Phi-4-mini，通用对话强、推理稳，写代码稍弱。约 2.3GB。",
        sizeOnDiskMB: 2300,
        recommended: false,
        tier: .small,
        architecture: "Phi-4-mini",
        downloadURLs: [
            URL(string: "https://huggingface.co/bartowski/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf")!,
            URL(string: "https://hf-mirror.com/bartowski/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf")!
        ],
        repo: "bartowski/Phi-4-mini-instruct-GGUF",
        filename: "Phi-4-mini-instruct-Q4_K_M.gguf"
    )

    static let all: [ModelCandidate] = [
        qwenCoder15bIQ3,
        qwenCoder7BQ4,
        deepSeekV2LiteQ4,
        kimiK25IQ3,
        doubaoPro32kQ4,
        phi4miniQ4
    ]
}
