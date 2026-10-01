// FileManager+Paths.swift
// © 2026 Trigin. All rights reserved.

import Foundation

enum AppPaths {

    /// ~/Library/Application Support/LocalCoder IDE/
    static func appSupport() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let url = base.appendingPathComponent("LocalCoder IDE", isDirectory: true)
        try? FileManager.default.createDirectory(at: url,
                                                withIntermediateDirectories: true)
        return url
    }

    /// 模型目录：~/Library/Application Support/LocalCoder IDE/models/
    static func modelsDir() -> URL {
        let url = appSupport().appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: url,
                                                withIntermediateDirectories: true)
        return url
    }

    /// 会话持久化：conversations.json
    static func conversationsFile() -> URL {
        appSupport().appendingPathComponent("conversations.json")
    }

    /// user defaults 里记录的当前模型路径
    static func stateFile() -> URL {
        appSupport().appendingPathComponent("state.json")
    }
}
