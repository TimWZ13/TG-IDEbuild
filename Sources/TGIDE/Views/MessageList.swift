// MessageList.swift
// © 2026 Trigin. All rights reserved.

import SwiftUI

struct MessageList: View {
    let messages: [ChatMessage]
    @State private var scrollBottom: ScrollViewProxy?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(messages) { m in
                        MessageBubble(message: m)
                            .id(m.id)
                    }
                    if messages.isEmpty {
                        WelcomeCard()
                            .padding(.top, 40)
                    }
                    // 锚点，保证滚到底
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .onAppear { scrollBottom = proxy; proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: messages.count) { _, _ in
                DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                roleLabel
                contentView
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var avatar: some View {
        ZStack {
            Circle()
                .fill(message.role.color.opacity(0.15))
            Image(systemName: message.role.icon)
                .foregroundStyle(message.role.color)
        }
        .frame(width: 28, height: 28)
    }

    private var roleLabel: some View {
        HStack(spacing: 6) {
            Text(message.role.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(DateFormatter.time.string(from: message.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if message.isStreaming {
                ProgressView().controlSize(.mini)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if message.role == .assistant || message.role == .tool {
            MarkdownView(text: message.content)
                .textSelection(.enabled)
        } else {
            Text(message.content)
                .textSelection(.enabled)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(message.role.color.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private extension DateFormatter {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

extension MessageRole {
    var displayName: String {
        switch self {
        case .system:    return "System"
        case .user:      return "你"
        case .assistant: return "TG IDE"
        case .tool:      return "Tool"
        }
    }
    var icon: String {
        switch self {
        case .system:    return "gearshape.fill"
        case .user:      return "person.fill"
        case .assistant: return "hammer.circle.fill"
        case .tool:      return "wrench.and.screwdriver.fill"
        }
    }
    var color: Color {
        switch self {
        case .system:    return .orange
        case .user:      return .blue
        case .assistant: return .purple
        case .tool:      return .green
        }
    }
}
