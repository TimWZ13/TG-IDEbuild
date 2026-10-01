// ToolRegistry.swift
// © 2026 Trigin. All rights reserved.
//
// 一个最小工具调用骨架。
// 本地 IDE 的核心能力是：
//   · read_file(path)              —— 读文件
//   · write_file(path, content)    —— 写文件
//   · run_command(cmd, cwd)        —— 在用户选定的目录下跑命令
//   · list_dir(path)               —— 列目录
//
// 真正把 tool call 接进推理循环需要做：
//   1. 在 chat() 的 sampler 之后检测模型输出的 tool-call 语法；
//   2. 解析 JSON 参数，调用 ToolRegistry；
//   3. 把 tool 结果以 role=tool 的 message 再塞回历史；
//   4. 循环继续 decode 直到模型结束。
//
// 本骨架已经把工具实现好，AppStore.send() 里留了 hook 位。
// 考虑到 llama.cpp chat 模板对 tool call 的支持依赖具体模型，
// 不同模型输出格式不一样（function_call tag / <tool> XML / 纯 JSON 等），
// 所以真正接 tool-loop 需要按当前模型的 chat_template 适配一次 parser。

import Foundation

enum ToolError: LocalizedError {
    case notAllowed(String)
    case io(String)
    case exec(String)

    var errorDescription: String? {
        switch self {
        case .notAllowed(let s): return "不允许：\(s)"
        case .io(let s):         return "IO：\(s)"
        case .exec(let s):       return "执行：\(s)"
        }
    }
}

struct ToolResult: Codable {
    let ok: Bool
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ToolRegistry {

    /// 当前工作目录（由用户在 UI 里设置；默认 ~/Desktop）
    static var workdir: URL = {
        let fm = FileManager.default
        return fm.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
    }()

    // MARK: - 工具 1：读文件

    @discardableResult
    static func readFile(path: String) throws -> String {
        let url = resolve(path: path)
        guard url.path.hasPrefix(workdir.path) || url.path.hasPrefix("/tmp") else {
            throw ToolError.notAllowed("仅允许读取 \(workdir.path) 或 /tmp 下的文件")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 工具 2：写文件

    @discardableResult
    static func writeFile(path: String, content: String) throws -> String {
        let url = resolve(path: path)
        guard url.path.hasPrefix(workdir.path) else {
            throw ToolError.notAllowed("仅允许写入 \(workdir.path) 下的文件")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return "OK \(url.path)"
    }

    // MARK: - 工具 3：列目录

    static func listDir(path: String = ".") throws -> [String] {
        let url = resolve(path: path)
        let items = try FileManager.default.contentsOfDirectory(at: url,
                                                                includingPropertiesForKeys: [.isRegularFileKey],
                                                                options: [.skipsHiddenFiles])
        return items.map { $0.lastPathComponent }.sorted()
    }

    // MARK: - 工具 4：跑命令

    static func runCommand(_ cmd: String, cwd: String? = nil, timeout: TimeInterval = 120) throws -> ToolResult {
        let url = cwd.map { resolve(path: $0) } ?? workdir
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", cmd]
        process.currentDirectoryURL = url

        let out = Pipe(); let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // 用 DispatchGroup 等进程退出
        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }

        try process.run()
        let _ = group.wait(timeout: .now() + timeout)
        if process.isRunning { process.terminate() }

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ToolResult(ok: process.terminationStatus == 0,
                          stdout: stdout, stderr: stderr,
                          exitCode: process.terminationStatus)
    }

    // MARK: - Helpers

    private static func resolve(path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return workdir.appendingPathComponent(path).standardizedFileURL
    }
}
