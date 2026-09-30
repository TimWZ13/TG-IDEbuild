// AppStore.swift
// © 2026 Trigin. All rights reserved.
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
    @Published var localModels: [URL] = []          // modelsDir 下的 gguf 文件
    @Published var activeModelPath: URL? = nil       // 当前被加载的
    @Published var isModelLoaded: Bool = false
    @Published var modelLoadMessage: String = ""

    // ── 下载 ────────────────────────────────────────────────
    @Published var downloader = ModelDownloader()

    // ── UI 状态 ──────────────────────────────────────────────
    @Published var isGenerating: Bool = false
    @Published var presentModelPanel: Bool = false
    @Published var statusLine: String = "就绪"

    private var llama: LlamaModel?

    // MARK: Init

    private init() {
        loadState()
        refreshLocalModels()
        // 默认选第一个 gguf
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

    func selectConversation(_ id: UUID) {
        selectedID = id
    }

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
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                 includingPropertiesForKeys: [.fileSizeKey],
                                                                 options: [.skipsHiddenFiles])) ?? []
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
            self.llama = m
            self.activeModelPath = path
            self.isModelLoaded = true
            self.modelLoadMessage = m.description
            self.statusLine = "已加载：\(m.description)"
            persistState()
        } catch {
            self.modelLoadMessage = error.localizedDescription
            self.statusLine = "加载失败：\(error.localizedDescription)"
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

    func send(message: String) async {
        guard var conv = currentConversation else { return }
        guard !isGenerating else { return }

        // 1. 追加用户消息
        let userMsg = ChatMessage.user(message)
        conv.messages.append(userMsg)
        if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
            conversations[idx] = conv
        }
        selectedID = conv.id

        // 2. 先放一条空的 assistant streaming 消息
        var assistantMsg = ChatMessage.assistant("", streaming: true)
        conv.messages.append(assistantMsg)

        isGenerating = true
        defer { isGenerating = false; statusLine = "就绪" }
        statusLine = activeModelPath == nil ? "请先加载模型" : "推理中…"

        guard let llama = llama else {
            // 没有模型 —— 给出友好占位回复
            if let idx = conversations.firstIndex(where: { $0.id == conv.id }),
               let last = conversations[idx].messages.lastIndex(where: { $0.isStreaming }) {
                conversations[idx].messages[last].content = "⚠️ 还没有加载模型。请先在右侧「模型」面板下载并加载一个 GGUF 文件。"
                conversations[idx].messages[last].isStreaming = false
                conversations[idx].updatedAt = Date()
            }
            persistConversations()
            return
        }

        // 3. 组装历史 messages
        var history: [(role: String, content: String)] = []
        for m in conv.messages.dropLast() {  // 去掉最后一条 streaming 占位
            let r: String
            switch m.role {
            case .assistant: r = "assistant"
            case .user:      r = "user"
            case .system:    r = "system"
            case .tool:      r = "tool"
            }
            history.append((role: r, content: m.content))
        }

        // 4. 调用 llama.chat + 逐 token 更新
        do {
            try llama.chat(
                system: conv.systemPrompt,
                messages: history,
                sampling: SamplingConfig(temperature: 0.7, topP: 0.95, maxTokens: 1024, seed: UInt32(Date().timeIntervalSince1970)),
                onToken: { [weak self] piece in
                    Task { @MainActor in
                        guard let self,
                              let idx = self.conversations.firstIndex(where: { $0.id == conv.id }),
                              let last = self.conversations[idx].messages.lastIndex(where: { $0.isStreaming })
                        else { return }
                        self.conversations[idx].messages[last].content += piece
                    }
                },
                onStop: { [weak self] in
                    Task { @MainActor in
                        guard let self,
                              let idx = self.conversations.firstIndex(where: { $0.id == conv.id }),
                              let last = self.conversations[idx].messages.lastIndex(where: { $0.isStreaming })
                        else { return }
                        self.conversations[idx].messages[last].isStreaming = false
                        self.conversations[idx].updatedAt = Date()
                        if self.conversations[idx].title == "新对话" &&
                            self.conversations[idx].messages.count >= 2 {
                            let preview = self.conversations[idx].messages.first { $0.role == .user }?.content ?? ""
                            self.conversations[idx].title = String(preview.prefix(24))
                        }
                        self.persistConversations()
                    }
                }
            )
        } catch {
            if let idx = conversations.firstIndex(where: { $0.id == conv.id }),
               let last = conversations[idx].messages.lastIndex(where: { $0.isStreaming }) {
                conversations[idx].messages[last].content += "\n\n❌ 推理失败：\(error.localizedDescription)"
                conversations[idx].messages[last].isStreaming = false
            }
        }
    }

    // MARK: - 持久化

    private func loadState() {
        let convURL = AppPaths.conversationsFile()
        if let data = try? Data(contentsOf: convURL),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = decoded
            selectedID = conversations.first?.id
        } else {
            // 首次启动：创建一个默认会话
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
        let state = StatePayload(
            activeModelPath: activeModelPath?.path
        )
        let url = AppPaths.stateFile()
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private struct StatePayload: Codable {
        var activeModelPath: String?
    }
}
