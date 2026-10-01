// MarkdownView.swift
// © 2026 Trigin. All rights reserved.
// Version: 0.2.0
//
// 轻量 Markdown 渲染（不引入 swift-markdown / swift-syntax 重依赖）。
// 解析并渲染：
//   · ```lang\n...\n```   → 代码块（带语言 tag + 暗色背景 + 等宽字体）
//   · `inline`             → inline code（浅色背景）
//   · **bold** / *italic*  → 简单粗斜
//   · 其它按段落输出
//
// 渲染走 NSTextView / NSAttributedString，保证可选择、可复制、可滚动。
// 遵循 NSViewRepresentable 协议，天然可在 SwiftUI ViewBuilder 中使用。

import SwiftUI
import AppKit

// MARK: - 主视图

/// macOS SwiftUI 可用的轻量 Markdown 渲染视图。
///
/// 使用方式：
/// ```swift
/// MarkdownView(text: "你好 **World** \n ```swift\nlet x = 1\n```")
/// ```
struct MarkdownView: NSViewRepresentable {

    // MARK: - 存储属性（全部显式类型，无推断）
    let text: String

    // MARK: - 显式初始化（避免 auto-init 丢失 / Stored properties inferred 警告）
    init(text: String) {
        self.text = text
    }

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 4, height: 4)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        textView.drawsBackground = false
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }

        let attributed: NSAttributedString = MarkdownParser.build(text)
        tv.textStorage?.setAttributedString(attributed)

        // 强制重新布局，让 NSScrollView / 父容器拿到正确高度
        if let container = tv.textContainer, let lm = tv.layoutManager {
            lm.ensureLayout(for: container)
            let usedHeight: CGFloat = lm.usedRect(for: container).height
            let finalHeight: CGFloat = max(usedHeight + 10, 20)
            tv.frame.size.height = finalHeight
            nsView.frame.size.height = finalHeight
        }
    }
}

// MARK: - MarkdownParser

/// 内部无状态解析器。独立成类型，避免闭包 / 类型推断问题。
private enum MarkdownParser {

    // ── 正则（类级常量，一次编译多使用） ──────────────────────
    private static let codeRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "`([^`]+)`")
    }()
    private static let boldRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\\*\\*([^*]+)\\*\\*")
    }()
    private static let italicRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)")
    }()

    // 占位 token（不可出现在正常文本里）
    private static let sentinelBegin: Character = "\u{0001}"
    private static let sentinelEnd:   Character = "\u{0002}"

    // ── 公共入口 ──────────────────────────────────────────────
    static func build(_ input: String) -> NSAttributedString {
        let out = NSMutableAttributedString()

        var codeBlocks: [CodeBlock] = []
        var plainRanges: [Range<String.Index>] = []
        parseCodeBlocks(from: input, codeBlocks: &codeBlocks, plainRanges: &plainRanges)

        // 交错渲染 plain → code → plain …
        var cursor: String.Index = input.startIndex
        for block in codeBlocks {
            if let plain = plainRanges.first(where: { $0.lowerBound == cursor }) {
                appendInline(to: out, plain: String(input[plain]))
                cursor = plain.upperBound
            }
            appendCodeBlock(to: out, block: block)
            cursor = block.range.upperBound
        }
        // 尾巴
        if let last = plainRanges.last,
           last.lowerBound >= cursor,
           !input[last].isEmpty {
            appendInline(to: out, plain: String(input[last]))
        }

        return out
    }

    // MARK: - Code block 拆分

    private struct CodeBlock {
        let language: String
        let body: String
        let range: Range<String.Index>
    }

    private static func parseCodeBlocks(
        from input: String,
        codeBlocks: inout [CodeBlock],
        plainRanges: inout [Range<String.Index>]
    ) {
        var searchStart: String.Index = input.startIndex
        while true {
            guard let openRange = input.range(of: "```", range: searchStart..<input.endIndex) else { break }
            plainRanges.append(searchStart..<openRange.lowerBound)

            let afterOpen: String.Index = openRange.upperBound
            let langEnd:   String.Index = input[afterOpen...].firstIndex(of: "\n") ?? input.endIndex
            let language:  String = String(input[afterOpen..<langEnd]).trimmingCharacters(in: .whitespaces)

            let searchSlice  = input[langEnd..<input.endIndex]
            guard let closeRange = searchSlice.range(of: "```") else { break }

            let bodyStart: String.Index = input.index(after: langEnd)
            let bodyEnd:   String.Index = closeRange.lowerBound

            codeBlocks.append(CodeBlock(
                language: language,
                body:     String(input[bodyStart..<bodyEnd]),
                range:    openRange.lowerBound..<closeRange.upperBound
            ))
            searchStart = closeRange.upperBound
        }
        plainRanges.append(searchStart..<input.endIndex)
    }

    // MARK: - Inline 解析（code / bold / italic）

    private static func appendInline(to out: NSMutableAttributedString, plain: String) {
        let baseFont:   NSFont = .preferredFont(forTextStyle: .body)
        let boldFont:   NSFont = .boldSystemFont(ofSize: baseFont.pointSize)
        let italicFont: NSFont = NSFontManager.shared.convert(
            .systemFont(ofSize: baseFont.pointSize),
            toHaveTrait: .italicFontMask
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2

        // 先把三类语法替换成带 sentinel 的占位，最后一次性拆分输出。
        // 倒序遍历 match 避免 range 偏移。
        let nsText = NSMutableString(string: plain)

        // inline code: `x`
        let codeMatches = codeRegex.matches(in: plain, range: NSRange(plain.startIndex..., in: plain))
        for match in codeMatches.reversed() {
            let bodySub = (plain as NSString).substring(with: NSRange(location: match.range.lowerBound + 1,
                                                                      length: match.range.length - 2))
            let repl = "\(sentinelBegin)CODE:\(bodySub)\(sentinelEnd)"
            nsText.replaceCharacters(in: match.range, with: repl)
        }

        // bold: **x**
        let boldMatches = boldRegex.matches(in: nsText as String, range: NSRange(location: 0, length: nsText.length))
        for match in boldMatches.reversed() {
            let bodySub = (nsText as NSString).substring(with: NSRange(location: match.range.lowerBound + 2,
                                                                      length: match.range.length - 4))
            let repl = "\(sentinelBegin)BOLD:\(bodySub)\(sentinelEnd)"
            nsText.replaceCharacters(in: match.range, with: repl)
        }

        // italic: *x*（非粗体匹配，负向前瞻/后顾）
        let italicMatches = italicRegex.matches(in: nsText as String, range: NSRange(location: 0, length: nsText.length))
        for match in italicMatches.reversed() {
            let bodySub = (nsText as NSString).substring(with: NSRange(location: match.range.lowerBound + 1,
                                                                      length: match.range.length - 2))
            let repl = "\(sentinelBegin)ITALIC:\(bodySub)\(sentinelEnd)"
            nsText.replaceCharacters(in: match.range, with: repl)
        }

        // 按 sentinel 切分，逐段追加到 out
        let final = nsText as String
        let components = final.split(separator: sentinelBegin, omittingEmptySubsequences: false)
        for rawToken in components {
            let token = String(rawToken)
            if token.hasSuffix(String(sentinelEnd)) {
                let inner = String(token.dropLast())
                if inner.hasPrefix("CODE:") {
                    let body = String(inner.dropFirst(5))
                    out.append(NSAttributedString(
                        string: body,
                        attributes: [
                            .font:            NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular),
                            .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.15),
                            .foregroundColor: NSColor.labelColor
                        ]
                    ))
                } else if inner.hasPrefix("BOLD:") {
                    out.append(NSAttributedString(
                        string: String(inner.dropFirst(5)),
                        attributes: [.font: boldFont, .paragraphStyle: paragraph]
                    ))
                } else if inner.hasPrefix("ITALIC:") {
                    out.append(NSAttributedString(
                        string: String(inner.dropFirst(7)),
                        attributes: [.font: italicFont, .paragraphStyle: paragraph]
                    ))
                } else {
                    // 未知前缀 — 原样输出，避免吞字
                    out.append(NSAttributedString(string: String(token.dropFirst()),
                                                  attributes: [.font: baseFont]))
                }
            } else {
                // 纯文本段
                out.append(NSAttributedString(
                    string: token,
                    attributes: [
                        .font:            baseFont,
                        .paragraphStyle:  paragraph,
                        .foregroundColor: NSColor.labelColor
                    ]
                ))
            }
        }
    }

    // MARK: - Code block 追加

    private static func appendCodeBlock(to out: NSMutableAttributedString, block: CodeBlock) {
        let mono      = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let darkBg    = NSColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1.0)
        let lightFg   = NSColor(red: 0.82, green: 0.86, blue: 0.92, alpha: 1.0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1

        // 顶部语言 tag
        let langLabel: String = block.language.isEmpty ? "code" : block.language
        out.append(NSAttributedString(
            string: "\n[ \(langLabel) ]\n",
            attributes: [
                .font:            NSFont.boldSystemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))

        // 代码体（保证末尾换行）
        let fullBody: String = block.body.hasSuffix("\n") ? block.body : block.body + "\n"
        out.append(NSAttributedString(
            string: fullBody,
            attributes: [
                .font:            mono,
                .foregroundColor: lightFg,
                .backgroundColor: darkBg,
                .paragraphStyle:  paragraph
            ]
        ))
    }
}
