// RootView.swift
// © 2026 Trigin. All rights reserved.
//
// 三栏布局：侧栏（会话列表）| 主对话 | 右侧模型/工具面板

import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var divider: CGFloat = 260

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            ChatPane()
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { store.newConversation() } label: {
                    Image(systemName: "plus")
                }
                .help("新建对话")

                Button { store.presentModelPanel = true } label: {
                    Image(systemName: "cpu")
                }
                .help("模型管理")

                Menu {
                    Button("清空当前会话") {
                        if var c = store.currentConversation {
                            c.messages.removeAll()
                            if let idx = store.conversations.firstIndex(where: { $0.id == c.id }) {
                                store.conversations[idx] = c
                            }
                        }
                    }
                    Button("重新加载当前会话的 System Prompt") {
                        if var c = store.currentConversation {
                            c.systemPrompt = SystemPrompts.defaultCoder
                            if let idx = store.conversations.firstIndex(where: { $0.id == c.id }) {
                                store.conversations[idx] = c
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("更多操作")
            }
        }
        .sheet(isPresented: $store.presentModelPanel) {
            ModelPanelView()
                .frame(minWidth: 560, minHeight: 420)
        }
        .overlay(alignment: .bottom) {
            StatusBar()
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
    }
}
