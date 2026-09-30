// LlamaModel.swift
// © 2026 Trigin. All rights reserved.
//
// llama.cpp 的最小 Swift 封装。提供：
//   · 从 GGUF 文件加载模型 + Metal GPU 后端
//   · 基于 llama_chat_apply_template 的 prompt 模板
//   · 同步 run 一次 + 流式 callback 逐 token 输出
//
// 注意：本文件依赖的 Cllama 模块由 Script/build_llama.sh 在首次构建时
//       用 llama.cpp 的真实头文件替换 Sources/llama_sources/include/llama.h。

import Foundation
import Cllama

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

public struct SamplingConfig {
    public var temperature: Float = 0.7
    public var topP: Float = 0.95
    public var topK: UInt32 = 40
    public var maxTokens: Int32 = 512
    public var seed: UInt32 = 0xC0FFEE
    public init() {}
}

public struct LlamaLoadOptions {
    public var nCtx: UInt32 = 2048
    public var nBatch: UInt32 = 512
    public var nGpuLayers: UInt32 = 99
    public var nThreads: UInt32 = 0
    public var useMetal: Bool = true
    public init() {}
}

public final class LlamaModel {

    public let path: String
    private let model: OpaquePointer?
    private let context: OpaquePointer?

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
        mparams.main_gpu = 0
        mparams.use_mlock = true
        mparams.use_mmap = true

        guard let model = llama_model_load_from_file(path, mparams) else {
            throw LlamaError.modelLoadFailed(path)
        }
        self.model = model

        var cparams = llama_context_default_params()
        cparams.n_ctx   = options.nCtx
        cparams.n_batch = options.nBatch
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

        // ---- 1. 构造 chat messages ----
        var roleCStrs: [[CChar]] = []
        var contentCStrs: [[CChar]] = []
        var chatMsgs: [llama_chat_message] = []

        // system
        roleCStrs.append(Array("system".utf8CString))
        contentCStrs.append(Array(system.utf8CString))
        chatMsgs.append(llama_chat_message(
            role: roleCStrs.last!.withUnsafeBufferPointer { $0.baseAddress },
            content: contentCStrs.last!.withUnsafeBufferPointer { $0.baseAddress }
        ))
        for msg in messages {
            roleCStrs.append(Array(msg.role.utf8CString))
            contentCStrs.append(Array(msg.content.utf8CString))
            chatMsgs.append(llama_chat_message(
                role: roleCStrs.last!.withUnsafeBufferPointer { $0.baseAddress },
                content: contentCStrs.last!.withUnsafeBufferPointer { $0.baseAddress }
            ))
        }
        let nMsgs = Int32(chatMsgs.count)

        // ---- 2. apply template ----
        var estimate: Int = 0
        for m in chatMsgs { estimate += Int(strlen(m.content)) }
        estimate += 256
        var needed: Int32 = 0
        let tmpBuf = UnsafeMutablePointer<Int8>.allocate(capacity: estimate)
        defer { tmpBuf.deallocate() }

        let applied = chatMsgs.withUnsafeBufferPointer { msgBuf in
            llama_chat_apply_template(
                model,
                nil,
                msgBuf.baseAddress,
                nMsgs,
                true,
                tmpBuf,
                Int32(estimate),
                &needed
            )
        }

        guard applied else {
            throw LlamaError.promptTemplateFailed("needed=\(needed)")
        }

        let prompt: String
        if needed > estimate {
            let bigBuf = UnsafeMutablePointer<Int8>.allocate(capacity: Int(needed))
            defer { bigBuf.deallocate() }
            _ = chatMsgs.withUnsafeBufferPointer { msgBuf in
                llama_chat_apply_template(
                    model, nil, msgBuf.baseAddress, nMsgs, true,
                    bigBuf, needed, nil
                )
            }
            prompt = String(cString: bigBuf)
        } else {
            prompt = String(cString: tmpBuf)
        }

        // ---- 3. tokenize ----
        var tokens: [Int32] = Array(repeating: 0, count: prompt.utf8.count + 64)
        var nTokVar: Int32 = Int32(tokens.count)

        let promptCStr = prompt.withCString { $0 }
        let tokOK = tokens.withUnsafeMutableBufferPointer { tokBuf in
            llama_tokenize(
                model, promptCStr,
                Int32(prompt.utf8.count + 1),
                tokBuf.baseAddress,
                nTokVar,
                false, true
            )
        }
        guard tokOK != 0, nTokVar > 0 else { throw LlamaError.tokenizeFailed }
        let nTok: Int32 = nTokVar

        // ---- 4. 清 KV cache ----
        llama_kv_cache_clear(ctx)

        // ---- 5. batch 初始化 ----
        let maxBatch: UInt32 = 512
        var batch = llama_batch_init(maxBatch, 0, 1)
        defer { llama_batch_free(&batch) }

        // ---- 6. 采样链 ----
        let sampParams = llama_sampler_chain_default_params()
        var sampler: OpaquePointer? = llama_sampler_chain_init(sampParams)
        defer { if let s = sampler { llama_sampler_free(s) } }

        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(sampling.topK))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(sampling.topP, sampling.seed))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(sampling.temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(sampling.seed))

        // ---- 7. 送入 prompt ----
        var off: Int32 = 0
        let maxBatchI32 = Int32(maxBatch)
        while off < nTok {
            let chunk = min(maxBatchI32, nTok - off)
            llama_batch_clear(&batch)
            for i in 0..<Int(chunk) {
                var seq: [Int32] = [0]
                llama_batch_add(&batch,
                                tokens[Int(off + Int32(i))],
                                UInt32(i), &seq, false)
            }
            if off + chunk == nTok {
                var seq: [Int32] = [0]
                llama_batch_add(&batch, 0, UInt32(chunk), &seq, true)
            }
            if llama_decode(ctx, batch) != 0 { throw LlamaError.decodeFailed }
            off += chunk
        }

        // ---- 8. 生成 loop ----
        var generated: Int32 = 0
        var prev: Int32 = 0
        let eos = llama_token_eos(model)
        let nl  = llama_token_nl(model)

        while generated < sampling.maxTokens {
            let id = llama_sampler_sample(sampler, ctx, -1)
            llama_sampler_accept(sampler, id)

            if id == eos { break }

            var idAsTok: Int32 = id
            var piece = [CChar](repeating: 0, count: 128)
            let n = llama_detokenize(model, &idAsTok, 1, &piece, Int32(piece.count), true, false)
            let text = n > 0 ? String(cString: piece) : ""

            if !text.isEmpty { onToken(text) }

            llama_kv_cache_seq_add(ctx, 0, 1, 0)
            llama_batch_clear(&batch)
            var seq: [Int32] = [0]
            llama_batch_add(&batch, id, 0, &seq, true)
            if llama_decode(ctx, batch) != 0 { break }

            prev = id
            generated += 1

            if prev == nl && id == nl { break }
        }

        onStop()
    }
}
