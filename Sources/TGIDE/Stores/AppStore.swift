// AppStore.swift
// © 2026 Trigin. All rights reserved.
// Version: 0.3.0
//
// 全局可观察状态：会话、模型、下载、推理中的任务。
// 主界面通过 .environmentObject(AppStore.shared) 注入。

import Foundation
import SwiftUI
import Combine
import LlamaBridge

@MainActor
final class AppStore: ObservableObject {

    static let shared = AppStore()

    // ── 会话 ────────────────────────────────────────────────
    @Published var conversations: [Conversation] = []
    @Published var selectedID: UUID?

    // ── 模型状态 ───────────────────────────────────────────
    @Published var localModels:    [URL] = []
    @Published var activeModelPath: URL? = nil
    @Published var isModelLoaded:  Bool = false
    @Published var modelLoadMessage: String = ""

    // ── 下载 ────────────────────────────────────────────────
    @Published var downloader = ModelDownloader()

    // ── UI 状态 ──────────────────────────────────────────────
    @Published var isGenerating:      Bool = false
    @Published var presentModelPanel: Bool = false
    @Published var statusLine:        String = "就绪"

    private var llama: LlamaModel?

    // MARK: Init

    private init() {
        loadState()
        refreshLocalModels()
        if activeModelPath == nil, let first = localModels.first {
            activeModelPath = first
        }
    }

    // MARK: - 会话操作

    var currentConversation: Conversation? {
        conversations.first { $0.id == selectedID } ?? conversations.first
    }

    func newConversation() {
        let c = Conversation.new()
        conversations.insert(c, at: 0)
        selectedID = c.id
        persistConversations()
    }

    func selectConversation(_ id: UUID) { selectedID = id }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedID == id { selectedID = conversations.first?.id }
        persistConversations()
    }

    func renameConversation(_ id: UUID, to title: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].title = title
        persistConversations()
    }

    // MARK: - 模型

    func refreshLocalModels() {
        let dir = AppPaths.modelsDir()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        localModels = urls.filter { $0.pathExtension.lowercased() == "gguf" }
    }

    func loadModel(path: URL) async {
        isModelLoaded = false
        llama = nil
        modelLoadMessage = "加载中…"
        statusLine = "加载模型 \(path.lastPathComponent)"
        do {
            var options = LlamaLoadOptions()
            options.nGpuLayers = 99
            options.nCtx = 4096
            let m = try LlamaModel(path: path.path, options: options)
            llama = m
            activeModelPath = path
            isModelLoaded = true
            modelLoadMessage = m.description
            statusLine = "已加载：\(m.description)"
            persistState()
        } catch {
            modelLoadMessage = error.localizedDescription
            statusLine = "加载失败：\(error.localizedDescription)"
        }
    }

    func unloadModel() {
        llama = nil
        isModelLoaded = false
        activeModelPath = nil
        modelLoadMessage = ""
        persistState()
    }

    func deleteLocalModel(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        if activeModelPath == url { unloadModel() }
        refreshLocalModels()
    }

    // MARK: - 生成

    /// 向当前会话追加用户消息并跑一次流式推理。
    /// llama.chat() 是同步阻塞 C API，必须扔到后台 Task.detached 里，
    /// 否则会卡住 MainActor → UI 冻结，onToken 的 Task { @MainActor } 也排队无法执行。
    func send(message: String) async {
        guard var conv = currentConversation else { return }
        guard !isGenerating else { return }

        // 1. 用户消息
        let userMsg = ChatMessage.user(message)
        conv.messages.append(userMsg)

        // 2. assistant streaming 占位 —— 必须立即写回 conversations 数组
        let streamingMsg = ChatMessage.assistant("", streaming: true)
        conv.messages.append(streamingMsg)

        var ci: Int = conversations.count
        if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
            conversations[idx] = conv
            ci = idx
        } else {
            conversations.insert(conv, at: conversations.endIndex)
            ci = conversations.endIndex - 1
        }
        selectedID = conv.id
        persistConversations()

        // 3. 状态
        isGenerating = true
        statusLine = activeModelPath == nil ? "请先加载模型" : "推理中…"

        // 4. 模型未加载 → 友好提示占位（不跑 llama）
        guard let llama else {
            if let last = conversations[ci].messages.lastIndex(where: { $0.isStreaming }) {
                conversations[ci].messages[last].content =
                    "⚠️ 还没有加载模型。请先在「模型」面板下载并加载一个 GGUF 文件。"
                conversations[ci].messages[last].isStreaming = false
                conversations[ci].updatedAt = Date()
            }
            persistConversations()
            isGenerating = false
            statusLine = "就绪"
            return
        }

        // 5. 组装参数（值类型，可安全跨 actor 边界捕获）
        let convID = conv.id
        let streamingID = streamingMsg.id
        let systemPrompt = conversations[ci].systemPrompt
        var history: [(role: String, content: String)] = []
        for m in conversations[ci].messages.dropLast() {
            let r: String
            switch m.role {
            case .assistant: r = "assistant"
            case .user:      r = "user"
            case .system:    r = "system"
            case .tool:      r = "tool"
            }
            history.append((role: r, content: m.content))
        }
        let sampling = SamplingConfig(
            temperature: 0.7, topP: 0.95,
            maxTokens: 1024,
            seed: UInt32(Date().timeIntervalSince1970)
        )

        // 6. 关键：后台线程跑 llama.chat，MainActor 不阻塞
        Task.detached { [weak self] in
            let result: Result<Void, Error> = Result {
                try llama.chat(
                    system: systemPrompt,
                    messages: history,
                    sampling: sampling,
                    onToken: { piece in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  let ci = self.conversations.firstIndex(where: { $0.id == convID }),
                                  let mi = self.conversations[ci].messages.firstIndex(where: { $0.id == streamingID })
                            else { return }
                            self.conversations[ci].messages[mi].content += piece
                        }
                    },
                    onStop: {
                        Task { @MainActor [weak self] in
                            guard let self,
                                  let ci = self.conversations.firstIndex(where: { $0.id == convID }),
                                  let mi = self.conversations[ci].messages.firstIndex(where: { $0.id == streamingID })
                            else { return }
                            self.conversations[ci].messages[mi].isStreaming = false
                            self.conversations[ci].updatedAt = Date()
                            if self.conversations[ci].title.hasPrefix("新对话"),
                               self.conversations[ci].messages.count >= 2,
                               let firstUser = self.conversations[ci].messages.first(where: { $0.role == .user }) {
                                self.conversations[ci].title = String(firstUser.content.prefix(24))
                            }
                            self.persistConversations()
                            self.isGenerating = false
                            self.statusLine = "就绪"
                        }
                    }
                )
            }

            // 错误处理（也在 MainActor 上更新 UI）
            if case .failure(let err) = result {
                Task { @MainActor [weak self] in
                    guard let self,
                          let ci = self.conversations.firstIndex(where: { $0.id == convID }),
                          let mi = self.conversations[ci].messages.firstIndex(where: { $0.id == streamingID })
                    else { return }
                    self.conversations[ci].messages[mi].content +=
                        "\n\n❌ 推理失败：\(err.localizedDescription)"
                    self.conversations[ci].messages[mi].isStreaming = false
                    self.isGenerating = false
                    self.statusLine = "就绪"
                }
            } else if case .success = result {
                // onStop 里已经处理 isGenerating = false；这里兜底（万一 onStop 没触发）
                Task { @MainActor [weak self] in
                    self?.isGenerating = false
                    self?.statusLine = "就绪"
                }
            }
        }
    }

    // MARK: - 持久化

    private func loadState() {
        let convURL = AppPaths.conversationsFile()
        if let data = try? Data(contentsOf: convURL),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: data),
           !decoded.isEmpty {
            conversations = decoded
            selectedID = conversations.first?.id
        } else {
            conversations = [Conversation.new()]
            selectedID = conversations.first?.id
        }

        let stateURL = AppPaths.stateFile()
        if let data = try? Data(contentsOf: stateURL),
           let state = try? JSONDecoder().decode(StatePayload.self, from: data) {
            activeModelPath = state.activeModelPath.flatMap { URL(fileURLWithPath: $0) }
        }
    }

    private func persistConversations() {
        let url = AppPaths.conversationsFile()
        if let data = try? JSONEncoder().encode(conversations) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func persistState() {
        let state = StatePayload(activeModelPath: activeModelPath?.path)
        let url = AppPaths.stateFile()
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private struct StatePayload: Codable {
        var activeModelPath: String?
    }
}
