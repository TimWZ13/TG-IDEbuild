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
            let options = LlamaLoadOptions()
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
    func send(message: String) async {
        guard var conv = currentConversation else { return }
        guard !isGenerating else { return }

        // 1. 用户消息
        let userMsg = ChatMessage.user(message)
        conv.messages.append(userMsg)

        // 2. assistant streaming 占位 —— ⚠️ 必须写回 conversations 数组，
        //    否则下面 onToken/onStop 闭包里 lastIndex(where: isStreaming) 永远 nil！
        let streamingMsg = ChatMessage.assistant("", streaming: true)
        conv.messages.append(streamingMsg)

        guard let idx = conversations.firstIndex(where: { $0.id == conv.id }) else {
            // 当前会话未加入数组 — 手动加入
            conversations.insert(conv, at: conversations.endIndex)
            selectedID = conv.id
        } else {
            conversations[idx] = conv   // ← 关键：一次性把 user + assistant 两条都写回
            selectedID = conv.id
        }
        persistConversations()

        // 3. 状态
        isGenerating = true
        defer { isGenerating = false; statusLine = "就绪" }
        statusLine = activeModelPath == nil ? "请先加载模型" : "推理中…"

        guard let llama else {
            if let idx = conversations.firstIndex(where: { $0.id == conv.id }),
               let last = conversations[idx].messages.lastIndex(where: { $0.isStreaming }) {
                conversations[idx].messages[last].content =
                    "⚠️ 还没有加载模型。请先在「模型」面板下载并加载一个 GGUF 文件。"
                conversations[idx].messages[last].isStreaming = false
                conversations[idx].updatedAt = Date()
            }
            persistConversations()
            return
        }

        // 4. 历史（去掉刚塞的 streaming 占位）
        var history: [(role: String, content: String)] = []
        let msgsForHistory = conversations[idx].messages.dropLast()
        for m in msgsForHistory {
            let r: String
            switch m.role {
            case .assistant: r = "assistant"
            case .user:      r = "user"
            case .system:    r = "system"
            case .tool:      r = "tool"
            }
            history.append((role: r, content: m.content))
        }

        // 5. 流式推理
        do {
            let streamingID = streamingMsg.id   // 用 ID 定位，比 isStreaming 更稳
            try llama.chat(
                system: conversations[idx].systemPrompt,
                messages: history,
                sampling: SamplingConfig(
                    temperature: 0.7, topP: 0.95,
                    maxTokens: 1024,
                    seed: UInt32(Date().timeIntervalSince1970)
                ),
                onToken: { [weak self] piece in
                    Task { @MainActor in
                        guard let self,
                              let ci = self.conversations.firstIndex(where: { $0.id == conv.id }),
                              let mi = self.conversations[ci].messages.firstIndex(where: { $0.id == streamingID })
                        else { return }
                        self.conversations[ci].messages[mi].content += piece
                    }
                },
                onStop: { [weak self] in
                    Task { @MainActor in
                        guard let self,
                              let ci = self.conversations.firstIndex(where: { $0.id == conv.id }),
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
                    }
                }
            )
        } catch {
            if let ci = conversations.firstIndex(where: { $0.id == conv.id }),
               let mi = conversations[ci].messages.firstIndex(where: { $0.id == streamingMsg.id }) {
                conversations[ci].messages[mi].content +=
                    "\n\n❌ 推理失败：\(error.localizedDescription)"
                conversations[ci].messages[mi].isStreaming = false
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
