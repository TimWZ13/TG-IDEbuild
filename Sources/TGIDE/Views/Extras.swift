// StatusBar.swift + WelcomeCard + SystemPromptEditor + ModelPanelView
// © 2026 Trigin. All rights reserved.

import SwiftUI

struct StatusBar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(store.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let p = store.activeModelPath {
                HStack(spacing: 6) {
                    Image(systemName: store.isModelLoaded ? "cpu.fill" : "cpu")
                    Text(p.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var statusColor: Color {
        if store.isGenerating { return .orange }
        if store.isModelLoaded { return .green }
        if store.activeModelPath != nil { return .yellow }
        return .gray
    }
}

struct WelcomeCard: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "hammer.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.purple.gradient)
            Text("TG IDE")
                .font(.title2.weight(.semibold))
            Text("本地轻量 AI 编码智能体 · 基于 llama.cpp + GGUF")
                .foregroundStyle(.secondary)
            Text("© 2026 Trigin")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Divider().padding(.horizontal, 60)
            Text("1. 打开「模型」面板 (⌘⇧M)\n2. 下载 Qwen2.5-Coder 1.5B · IQ3_M (推荐)\n3. 回到这里开始聊天")
                .multilineTextAlignment(.leading)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(24)
        .background(.quaternary.opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SystemPromptEditor: View {
    @Binding var conv: Conversation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("System Prompt")
                    .font(.headline)
                Spacer()
                Button("恢复默认") {
                    conv.systemPrompt = SystemPrompts.defaultCoder
                }
                Button("极简版") {
                    conv.systemPrompt = SystemPrompts.minimal
                }
            }
            TextEditor(text: $conv.systemPrompt)
                .font(.system(.body, design: .monospaced))
            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }
}

// ─── 模型管理面板 ──────────────────────────────────────────────

struct ModelPanelView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            TabView {
                catalogTab.tabItem { Label("推荐模型", systemImage: "star") }
                localTab.tabItem   { Label("本地", systemImage: "folder") }
            }
            .padding(.horizontal, 14)
            Spacer(minLength: 0)
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Text("模型管理")
                .font(.title3.weight(.semibold))
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .help("关闭")
        }
        .padding(14)
    }

    private var catalogTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(ModelCatalog.all) { c in
                    modelRow(c)
                }
            }
            .padding(.vertical, 10)
        }
    }

    private func modelRow(_ c: ModelCandidate) -> some View {
        let isCurrentCandidate = {
            if case .downloading(let cc, _, _, _) = store.downloader.state { return cc.id == c.id }
            if case .paused(let cc) = store.downloader.state { return cc.id == c.id }
            if case .success(let cc, _) = store.downloader.state { return cc.id == c.id }
            if case .failed(let cc, _) = store.downloader.state { return cc.id == c.id }
            return false
        }()
        let progress: Double = {
            if case .downloading(_, _, let received, let total?) = store.downloader.state,
               let expectedBytes = totalIf(c) {
                return Double(received) / Double(expectedBytes)
            }
            return 0
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(c.displayName).font(.headline)
                        if c.recommended {
                            Tag(text: "推荐", color: .green)
                        }
                    }
                    Text(c.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if localFileExists(c) {
                    Button {
                        Task { await store.loadModel(path: localURL(c)) }
                    } label: {
                        Text(store.activeModelPath?.lastPathComponent == c.filename
                             && store.isModelLoaded ? "已加载" : "加载")
                            .padding(.horizontal, 10).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    if isCurrentCandidate {
                        downloadControls(c)
                    } else {
                        Button {
                            store.downloader.download(c)
                        } label: {
                            Label("下载", systemImage: "arrow.down.circle")
                                .padding(.horizontal, 10).padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            HStack {
                Text("~ \(c.sizeOnDiskMB / 1024)GB").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                if case .downloading(_, _, let r, let t?) = store.downloader.state,
                   let expected = totalIf(c) {
                    ProgressView(value: Double(r), total: Double(expected))
                        .frame(width: 180)
                    Text("\(Int(Double(r)/1_000_000)) / \(expected/1_000_000) MB")
                        .font(.caption2).foregroundStyle(.secondary)
                } else if isCurrentCandidate,
                          case .downloading(_, _, _, nil) = store.downloader.state {
                    ProgressView().frame(width: 180)
                    Text("连接中…").font(.caption2).foregroundStyle(.secondary)
                } else if case .failed(let cc, let msg) = store.downloader.state, cc.id == c.id {
                    Text("⚠️ \(msg)").font(.caption2).foregroundStyle(.red)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func downloadControls(_ c: ModelCandidate) -> some View {
        HStack(spacing: 6) {
            if case .paused = store.downloader.state {
                Button { store.downloader.resume() } label: { Text("继续") }
                    .buttonStyle(.bordered)
            } else {
                Button { store.downloader.pause() } label: { Text("暂停") }
                    .buttonStyle(.bordered)
            }
            Button(role: .destructive) { store.downloader.cancel() } label: { Text("取消") }
                .buttonStyle(.bordered)
        }
    }

    private func totalIf(_ c: ModelCandidate) -> Int64? {
        if case .downloading(_, _, _, let t) = store.downloader.state { return t }
        return nil
    }

    private func localFileExists(_ c: ModelCandidate) -> Bool {
        FileManager.default.fileExists(atPath: localURL(c).path)
    }
    private func localURL(_ c: ModelCandidate) -> URL {
        AppPaths.modelsDir().appendingPathComponent(c.filename)
    }

    private var localTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.localModels.isEmpty {
                ContentUnavailableView("还没有下载的模型", systemImage: "shippingbox",
                                       description: Text("从「推荐模型」页挑一个下吧。"))
            } else {
                ForEach(store.localModels, id: \.self) { url in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(url.lastPathComponent).font(.body)
                            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                               let sz = attrs[.size] as? NSNumber {
                                Text(String(format: "%.1f MB", sz.doubleValue / 1_000_000))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if store.activeModelPath == url && store.isModelLoaded {
                            Tag(text: "已加载", color: .green)
                        }
                        Button {
                            Task { await store.loadModel(path: url) }
                        } label: { Text("加载") }.buttonStyle(.bordered)
                        Button(role: .destructive) {
                            store.deleteLocalModel(url)
                        } label: { Image(systemName: "trash") }.buttonStyle(.bordered)
                    }
                }
            }
            Divider().padding(.top, 6)
            HStack {
                Button("手动选择 GGUF…") {
                    chooseFile()
                }
                Text("模型目录：\(AppPaths.modelsDir().path)")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Text(AppMeta.copyright).font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Text("v\(AppMeta.version) (\(AppMeta.build))")
                .font(.caption2).foregroundStyle(.secondary)
            Button("关闭") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(10)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "gguf")].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url {
            let dest = AppPaths.modelsDir().appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: dest)
            store.refreshLocalModels()
            Task { await store.loadModel(path: dest) }
        }
    }
}

struct Tag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15),
                        in: Capsule())
            .foregroundStyle(color)
    }
}
