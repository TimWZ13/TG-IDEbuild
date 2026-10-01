// ChatPane.swift
// © 2026 Trigin. All rights reserved.

import SwiftUI

struct ChatPane: View {
    @EnvironmentObject var store: AppStore
    @State private var input: String = ""
    @State private var showPrompt = false

    var body: some View {
        VStack(spacing: 0) {
            if let conv = store.currentConversation {
                topBar(conv)
                MessageList(messages: conv.messages)
                Divider()
                PromptBar(text: $input, showSystemPrompt: $showPrompt) {
                    await submit()
                }
                .disabled(store.isGenerating)
                .padding(10)
            } else {
                ContentUnavailableView("没有会话", systemImage: "tray",
                                       description: Text("点 ⌘N 或 + 新建一个"))
            }
        }
    }

    private func topBar(_ conv: Conversation) -> some View {
        HStack {
            Text(conv.title)
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                showPrompt.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("System Prompt")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .sheet(isPresented: $showPrompt) {
            SystemPromptEditor(conv: Binding(
                get: { conv },
                set: { new in
                    if let idx = store.conversations.firstIndex(where: { $0.id == conv.id }) {
                        store.conversations[idx] = new
                    }
                }
            ))
            .frame(width: 560, height: 380)
        }
    }

    private func submit() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        input = ""
        await store.send(message: trimmed)
    }
}
