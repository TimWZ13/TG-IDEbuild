// PromptBar.swift
// © 2026 Trigin. All rights reserved.

import SwiftUI

struct PromptBar: View {
    @Binding var text: String
    @Binding var showSystemPrompt: Bool
    var onSend: () async -> Void

    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 44, maxHeight: 180)
                        .overlay(
                            Group {
                                if text.isEmpty {
                                    Text(placeholder)
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 10)
                                        .allowsHitTesting(false)
                                }
                            }, alignment: .topLeading)
                }
                .padding(6)
                .background(.quaternary.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    Task { await onSend() }
                } label: {
                    Image(systemName: store.isGenerating ? "stop.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 26))
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var placeholder: String {
        if store.activeModelPath == nil {
            return "先到右侧模型面板下载一个 GGUF…"
        }
        return "问点什么。⌘↩ 发送，Shift↩ 换行。"
    }
}
