// SidebarView.swift
// © 2026 Trigin. All rights reserved.

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            List(selection: Binding(
                get: { store.selectedID },
                set: { store.selectedID = $0 }
            )) {
                ForEach(store.conversations) { conv in
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conv.title)
                                .lineLimit(1)
                                .font(.headline)
                            Text(DateFormatter.short.string(from: conv.updatedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.selectedID = conv.id }
                    .contextMenu {
                        Button("重命名") {
                            rename(conv)
                        }
                        Button("删除", role: .destructive) {
                            store.deleteConversation(conv.id)
                        }
                    }
                    .tag(conv.id)
                }
                .onDelete { indexSet in
                    for i in indexSet {
                        store.deleteConversation(store.conversations[i].id)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 220)
    }

    private var header: some View {
        HStack {
            Label("TG IDE", systemImage: "hammer.circle.fill")
                .font(.headline)
            Spacer()
            Button { store.newConversation() } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("新建对话")
        }
        .padding(12)
    }

    private func rename(_ conv: Conversation) {
        let alert = NSAlert()
        alert.messageText = "重命名会话"
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        tf.stringValue = conv.title
        alert.accessoryView = tf
        alert.window.makeFirstResponder(tf)
        if alert.runModal() == .alertFirstButtonReturn {
            store.renameConversation(conv.id, to: tf.stringValue)
        }
    }
}
