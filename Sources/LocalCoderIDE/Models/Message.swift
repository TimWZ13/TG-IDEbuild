// Message.swift
// © 2026 Trigin. All rights reserved.

import Foundation

enum MessageRole: String, Codable, CaseIterable, Identifiable {
    case system, user, assistant, tool
    var id: String { rawValue }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var role: MessageRole
    var content: String
    var createdAt: Date = Date()
    /// 模型输出可能流式到达，isStreaming=true 表示还在写
    var isStreaming: Bool = false
    /// 如果这是 tool call 的占位，记录一下名字方便 UI
    var toolName: String? = nil

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, content: text)
    }
    static func assistant(_ text: String, streaming: Bool = false) -> ChatMessage {
        ChatMessage(role: .assistant, content: text, isStreaming: streaming)
    }
    static func system(_ text: String) -> ChatMessage {
        ChatMessage(role: .system, content: text)
    }
}
