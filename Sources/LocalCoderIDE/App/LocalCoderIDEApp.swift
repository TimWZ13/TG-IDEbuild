// LocalCoderIDEApp.swift
// © 2026 Trigin. All rights reserved.
// Version: 0.1.0
//
// App 入口。遵循 macOS SwiftUI 2024 推荐形态。
// 启动时做两件事：
//   1. 设置 NSApp 激活策略为 regular（否则 Dock 上可能没图标）；
//   2. 初始化全局 AppStore（模型下载/会话管理）。

import SwiftUI
import AppKit

@main
struct LocalCoderIDEApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        // 强制 Dock 图标 + 前台激活
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("LocalCoder IDE") {
            RootView()
                .frame(minWidth: 960, minHeight: 600)
                .environmentObject(AppStore.shared)
        }
        .windowStyle(.hiddenTitleBar)  // 侧边栏/工具栏全自定义
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 LocalCoder IDE") {
                    showAbout()
                }
            }
            CommandGroup(after: .appSettings) {
                Button("检查模型更新…") {
                    AppStore.shared.presentModelPanel = true
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }

    private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "LocalCoder IDE · v0.1.0"
        alert.informativeText = """
        本地轻量 AI 编码智能体
        Powered by llama.cpp · GGUF
        
        © 2026 Trigin. All rights reserved.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

// AppDelegate 占位；未来可在这里挂菜单项、全局快捷键
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 统一 logging 标记
    }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
