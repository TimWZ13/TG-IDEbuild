// Conversation.swift
// © 2026 Trigin. All rights reserved.

import Foundation

struct Conversation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var messages: [ChatMessage] = []
    var systemPrompt: String = SystemPrompts.defaultCoder

    static func new() -> Conversation {
        Conversation(title: "新对话 · \(DateFormatter.short.string(from: Date()))")
    }
}

extension DateFormatter {
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}
