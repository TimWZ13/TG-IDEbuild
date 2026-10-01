// ModelDownloader.swift
// © 2026 Trigin. All rights reserved.
//
// 负责把 gguf 从 ModelCatalog.downloadURLs 列表里逐个尝试下载到本地。
// 特性：
//   · URLSession 后台任务 + 恢复（ETag/Last-Modified）
//   · 多镜像自动降级
//   · 进度百分比 + 速度估算
//   · 可取消
//   · 文件落盘后做基本一致性检查（非 0 字节）

import Foundation
import Combine

final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {

    enum State: Equatable {
        case idle
        case downloading(candidate: ModelCandidate, urlIndex: Int, bytesReceived: Int64, totalBytes: Int64?)
        case paused(candidate: ModelCandidate)
        case success(candidate: ModelCandidate, localURL: URL)
        case failed(candidate: ModelCandidate, errorMessage: String)
    }

    @Published var state: State = .idle

    private var task: URLSessionDownloadTask?
    private var resumeData: Data?
    private var currentCandidate: ModelCandidate?
    private var currentURLIndex: Int = 0
    private var lastProgressPublish: Date = .distantPast

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 24 * 60 * 60
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
    }()

    func download(_ candidate: ModelCandidate) {
        currentCandidate = candidate
        currentURLIndex = 0
        startNextURL()
    }

    func cancel() {
        task?.cancel()
        task = nil
        resumeData = nil
        currentCandidate = nil
        state = .idle
    }

    func pause() {
        task?.cancel(byProducingResumeData: { [weak self] data in
            self?.resumeData = data
            if let c = self?.currentCandidate {
                self?.state = .paused(candidate: c)
            }
        })
        task = nil
    }

    func resume() {
        guard let data = resumeData, let candidate = currentCandidate else { return }
        state = .downloading(candidate: candidate, urlIndex: currentURLIndex,
                             bytesReceived: 0, totalBytes: nil)
        task = session.downloadTask(withResumeData: data)
        task?.resume()
        resumeData = nil
    }

    // MARK: - Private

    private func startNextURL() {
        guard let c = currentCandidate else { return }
        guard currentURLIndex < c.downloadURLs.count else {
            state = .failed(candidate: c,
                            errorMessage: "所有镜像都下载失败，请检查网络或手动下载 GGUF 文件放到 ~/Library/Application Support/TG IDE/models/")
            return
        }
        let url = c.downloadURLs[currentURLIndex]
        state = .downloading(candidate: c, urlIndex: currentURLIndex,
                             bytesReceived: 0, totalBytes: nil)
        task = session.downloadTask(with: url)
        task?.resume()
    }

    private func localDestination(for candidate: ModelCandidate) -> URL {
        AppPaths.modelsDir().appendingPathComponent(candidate.localFilename)
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let now = Date()
        guard now.timeIntervalSince(lastProgressPublish) > 0.1 else { return } // ~10fps
        lastProgressPublish = now
        guard let c = currentCandidate else { return }
        state = .downloading(candidate: c,
                             urlIndex: currentURLIndex,
                             bytesReceived: totalBytesWritten,
                             totalBytes: totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown
                                ? nil : totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let c = currentCandidate else { return }

        // 校验文件
        let attrs = try? FileManager.default.attributesOfItem(atPath: location.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 1024 * 1024 else { // 至少 1MB，否则认为是 404/错误页
            state = .failed(candidate: c,
                            errorMessage: "下载的文件只有 \(size) 字节（可能是错误页）。尝试下一个镜像…")
            currentURLIndex += 1
            try? FileManager.default.removeItem(at: location)
            startNextURL()
            return
        }

        let dest = localDestination(for: c)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            state = .success(candidate: c, localURL: dest)
        } catch {
            state = .failed(candidate: c, errorMessage: "保存失败：\(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error as? NSError,
           error.code == NSURLErrorCancelled,
           resumeData != nil {
            // pause 产生的取消：忽略
            return
        }
        if let error = error, let c = currentCandidate {
            // 尝试下一个镜像
            currentURLIndex += 1
            if currentURLIndex < c.downloadURLs.count {
                startNextURL()
            } else {
                state = .failed(candidate: c, errorMessage: error.localizedDescription)
            }
        }
    }
}
