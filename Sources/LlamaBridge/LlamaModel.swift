// LlamaModel.swift
// © 2026 Trigin. All rights reserved.
// Version: 0.3.0
//
// llama.cpp 的最小 Swift 封装。
//   · GGUF 加载 + Metal GPU 后端
//   · llama_chat_apply_template 模板
//   · 同步 chat() + 流式 token 回调
//
// 本文件依赖 Sources/Cllama/Include/llama.h；
// Script/build_llama.sh 首次运行会用 llama.cpp 官方头文件覆盖它。

import Foundation
import Cllama

// MARK: - Error

public enum LlamaError: LocalizedError {
    case backendLoadFailed(String)
    case modelLoadFailed(String)
    case contextInitFailed
    case promptTemplateFailed(String)
    case tokenizeFailed
    case decodeFailed
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .backendLoadFailed(let s):    return "llama 后端加载失败: \(s)"
        case .modelLoadFailed(let s):      return "模型加载失败: \(s)"
        case .contextInitFailed:           return "上下文初始化失败"
        case .promptTemplateFailed(let s): return "prompt 模板失败: \(s)"
        case .tokenizeFailed:              return "token 化失败"
        case .decodeFailed:                return "decode 失败"
        case .unsupported(let s):          return "不支持: \(s)"
        }
    }
}

// MARK: - Config structs

public struct SamplingConfig {
    public var temperature: Float
    public var topP:        Float
    public var topK:        UInt32
    public var maxTokens:   Int32
    public var seed:        UInt32
    public init(
        temperature: Float = 0.7,
        topP:        Float = 0.95,
        topK:        UInt32 = 40,
        maxTokens:   Int32 = 512,
        seed:        UInt32 = 0xC0FFEE
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.seed = seed
    }
}

public struct LlamaLoadOptions {
    public var nCtx:      UInt32
    public var nBatch:    UInt32
    public var nGpuLayers: UInt32
    public var nThreads:  UInt32
    public var useMetal:  Bool
    public init(
        nCtx:       UInt32 = 2048,
        nBatch:     UInt32 = 512,
        nGpuLayers: UInt32 = 99,
        nThreads:   UInt32 = 0,
        useMetal:   Bool = true
    ) {
        self.nCtx = nCtx
        self.nBatch = nBatch
        self.nGpuLayers = nGpuLayers
        self.nThreads = nThreads
        self.useMetal = useMetal
    }
}

// MARK: - LlamaModel

public final class LlamaModel {

    public let path: String
    private let model:   OpaquePointer?
    private let context: OpaquePointer?

    // MARK: - Init

    public init(path: String, options: LlamaLoadOptions = LlamaLoadOptions()) throws {
        self.path = path

        llama_backend_init()

        if options.useMetal {
            if !llama_backend_load_from_file("ggml-metal", nil) {
                throw LlamaError.backendLoadFailed("ggml-metal")
            }
        }

        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = Int32(options.nGpuLayers)
        mparams.main_gpu     = 0
        mparams.use_mlock    = true
        mparams.use_mmap     = true

        guard let model = llama_model_load_from_file(path, mparams) else {
            throw LlamaError.modelLoadFailed(path)
        }
        self.model = model

        var cparams = llama_context_default_params()
        cparams.n_ctx     = options.nCtx
        cparams.n_batch   = options.nBatch
        cparams.n_threads = options.nThreads == 0
            ? UInt32(max(1, ProcessInfo.processInfo.activeProcessorCount))
            : options.nThreads

        guard let ctx = llama_new_context_with_model(model, cparams) else {
            llama_model_free(model)
            throw LlamaError.contextInitFailed
        }
        self.context = ctx
    }

    deinit {
        if let ctx = context { llama_free(ctx) }
        if let m   = model  { llama_model_free(m) }
        llama_backend_free()
    }

    // MARK: - Queries

    public var nCtxTrain: UInt32 {
        guard let m = model else { return 0 }
        return UInt32(llama_model_n_ctx_train(m))
    }

    public var description: String {
        guard let m = model else { return "" }
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: 256)
        defer { buf.deallocate() }
        llama_model_desc(m, buf, 256)
        return String(cString: buf)
    }

    // MARK: - chat (streaming)

    public func chat(
        system: String,
        messages: [(role: String, content: String)],
        sampling: SamplingConfig = SamplingConfig(),
        onToken: @escaping (String) -> Void,
        onStop:  @escaping () -> Void = {}
    ) throws {
        guard let model = model, let ctx = context else {
            throw LlamaError.unsupported("model 未初始化")
        }

        // ──────────────────────────────────────────────
        // 1. 构造 chat messages — 必须让 CString 生命周期
        //    覆盖整个 chat() 调用（CStrings 数组本身活到函数返回）。
        // ──────────────────────────────────────────────
        let rolePool:   [[CChar]] = [Array("system".utf8CString)] +
            messages.map { Array($0.role.utf8CString) }
        let contentPool: [[CChar]] = [Array(system.utf8CString)] +
            messages.map { Array($0.content.utf8CString) }

        var chatMsgs: [llama_chat_message] = []
        chatMsgs.reserveCapacity(rolePool.count)
        for i in 0..<rolePool.count {
            let rolePtr   = rolePool[i].withUnsafeBufferPointer { $0.baseAddress }
            let contentPtr = contentPool[i].withUnsafeBufferPointer { $0.baseAddress }
            chatMsgs.append(llama_chat_message(role: rolePtr, content: contentPtr))
        }
        // 显式保留到函数末尾，防止编译器过早释放
        defer { _ = rolePool; _ = contentPool }

        // ──────────────────────────────────────────────
        // 2. apply chat template
        // ──────────────────────────────────────────────
        var estimate: Int = 0
        for m in chatMsgs { estimate += Int(strlen(m.content)) }
        estimate += 256

        let prompt: String = try {
            var needed: Int32 = 0
            let tmpBuf = UnsafeMutablePointer<Int8>.allocate(capacity: estimate)
            defer { tmpBuf.deallocate() }

            let ok = chatMsgs.withUnsafeBufferPointer { msgBuf in
                llama_chat_apply_template(
                    model, nil, msgBuf.baseAddress,
                    Int32(chatMsgs.count), true,
                    tmpBuf, Int32(estimate), &needed
                )
            }
            guard ok else { throw LlamaError.promptTemplateFailed("needed=\(needed)") }

            if needed > estimate {
                let bigBuf = UnsafeMutablePointer<Int8>.allocate(capacity: Int(needed))
                defer { bigBuf.deallocate() }
                _ = chatMsgs.withUnsafeBufferPointer { msgBuf in
                    llama_chat_apply_template(
                        model, nil, msgBuf.baseAddress,
                        Int32(chatMsgs.count), true,
                        bigBuf, needed, nil
                    )
                }
                return String(cString: bigBuf)
            }
            return String(cString: tmpBuf)
        }()

        // ──────────────────────────────────────────────
        // 3. tokenize（C stub 已修复 n_tokens 为指针）
        // ──────────────────────────────────────────────
        var tokens: [Int32] = Array(repeating: 0, count: prompt.utf8.count + 64)
        var nTok:   Int32   = Int32(tokens.count)

        let tokOK = prompt.withCString { promptCStr in
            tokens.withUnsafeMutableBufferPointer { tokBuf in
                llama_tokenize(
                    model, promptCStr,
                    Int32(prompt.utf8.count + 1),
                    tokBuf.baseAddress,
                    &nTok,
                    false, true
                )
            }
        }
        guard tokOK >= 0, nTok > 0 else { throw LlamaError.tokenizeFailed }

        // ──────────────────────────────────────────────
        // 4. KV cache + batch + sampler
        // ──────────────────────────────────────────────
        llama_kv_cache_clear(ctx)

        let maxBatch: UInt32 = 512
        var batch = llama_batch_init(maxBatch, 0, 1)
        defer { llama_batch_free(&batch) }

        let sampParams = llama_sampler_chain_default_params()
        let sampler = llama_sampler_chain_init(sampParams)
        defer { if let s = sampler { llama_sampler_free(s) } }

        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(sampling.topK))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(sampling.topP, sampling.seed))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(sampling.temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(sampling.seed))

        // ──────────────────────────────────────────────
        // 5. prompt 送入
        // ──────────────────────────────────────────────
        var off: Int32 = 0
        let maxBatchI32: Int32 = Int32(maxBatch)
        while off < nTok {
            let chunk = min(maxBatchI32, nTok - off)
            llama_batch_clear(&batch)
            for i in 0..<Int(chunk) {
                var seq: [Int32] = [0]
                llama_batch_add(
                    &batch,
                    tokens[Int(off + Int32(i))],
                    UInt32(i), &seq, false
                )
            }
            // prompt 最后一个 token 上开 logits
            if off + chunk == nTok {
                var seq: [Int32] = [0]
                llama_batch_add(&batch, 0, UInt32(chunk), &seq, true)
            }
            if llama_decode(ctx, batch) != 0 { throw LlamaError.decodeFailed }
            off += chunk
        }

        // ──────────────────────────────────────────────
        // 6. 生成 loop
        // ──────────────────────────────────────────────
        let eos = llama_token_eos(model)
        let nl  = llama_token_nl(model)
        var generated: Int32 = 0
        var prev: Int32 = 0

        while generated < sampling.maxTokens {
            let id = llama_sampler_sample(sampler, ctx, -1)
            llama_sampler_accept(sampler, id)

            if id == eos { break }

            // detokenize
            var tokBufId: Int32 = id
            var piece: [CChar] = [CChar](repeating: 0, count: 128)
            let n = llama_detokenize(
                model, &tokBufId, 1,
                &piece, Int32(piece.count),
                true, false
            )
            if n > 0 { onToken(String(cString: piece)) }

            // 送回 KV cache
            llama_kv_cache_seq_add(ctx, 0, 1, 0)
            llama_batch_clear(&batch)
            var seq: [Int32] = [0]
            llama_batch_add(&batch, id, 0, &seq, true)
            if llama_decode(ctx, batch) != 0 { break }

            prev = id
            generated += 1
            // 连续两个换行 = 停止（避免重复）
            if prev == nl && id == nl { break }
        }

        onStop()
    }
}
