// MarkdownView.swift
// © 2026 Trigin. All rights reserved.
//
// 为了避免对 swift-markdown / swift-syntax 这类重依赖，
// 这里用一个非常轻量的自写 parser：
//   · ```lang\n...\n```   → 代码块（带语言标记 + 复制按钮）
//   · `inline`             → inline code
//   · **bold** / *italic*  → 简单粗斜
//   · 其它按段落输出
// 渲染走 NSTextView/NSAttributedString，保证可选择、可复制。

import SwiftUI
import AppKit

struct MarkdownView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.preferredFont(forTextStyle: .body)

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
        let attr = buildAttributed(text)
        tv.textStorage?.setAttributedString(attr)
        // 强制重新布局
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let h = tv.layoutManager?.usedRect(for: tv.textContainer!).height ?? 20
        tv.frame.size.height = max(h + 10, 20)
        nsView.frame.size.height = tv.frame.height
    }

    // MARK: - Parser

    private struct CodeBlock {
        let language: String
        let body: String
        let range: Range<String.Index>
    }

    private func buildAttributed(_ input: String) -> NSAttributedString {
        let out = NSMutableAttributedString()

        // 1. 先把 ```...``` 代码块切出来
        var plainRanges: [Range<String.Index>] = []
        var codeBlocks: [CodeBlock] = []
        var searchStart = input.startIndex
        while true {
            guard let openRange = input.range(of: "```", range: searchStart..<input.endIndex) else { break }
            // 记录代码块之前的 plain
            plainRanges.append(searchStart..<openRange.lowerBound)
            // 读 language
            let afterOpen = openRange.upperBound
            let langEnd = input[afterOpen...].firstIndex(of: "\n") ?? input.endIndex
            let lang = String(input[afterOpen..<langEnd]).trimmingCharacters(in: .whitespaces)
            // 找 closing ```
            let search = input[langEnd..<input.endIndex]
            guard let closeRange = search.range(of: "```") else { break }
            let bodyStart = input.index(after: langEnd)
            let bodyEnd = closeRange.lowerBound
            codeBlocks.append(CodeBlock(language: lang,
                                        body: String(input[bodyStart..<bodyEnd]),
                                        range: openRange.lowerBound..<closeRange.upperBound))
            searchStart = closeRange.upperBound
        }
        plainRanges.append(searchStart..<input.endIndex)

        // 2. 交错渲染：plain -> code -> plain -> code -> plain
        var cursor = input.startIndex
        for block in codeBlocks {
            if let plainRange = plainRanges.first(where: { $0.lowerBound == cursor }) {
                appendInline(&out, plain: String(input[plainRange]))
                cursor = plainRange.upperBound
            }
            appendCodeBlock(&out, block: block)
            cursor = block.range.upperBound
        }
        // 尾巴
        if let lastPlain = plainRanges.last,
           lastPlain.lowerBound >= cursor,
           !input[lastPlain].isEmpty {
            appendInline(&out, plain: String(input[lastPlain]))
        }

        return out
    }

    private func appendInline(_ out: NSMutableAttributedString, plain: String) {
        // 轻量处理：inline code / **bold** / *italic*
        var text = plain
        let baseFont = NSFont.preferredFont(forTextStyle: .body)
        let boldFont = NSFont.boldSystemFont(ofSize: baseFont.pointSize)
        let italicFont = NSFont.systemFont(ofSize: baseFont.pointSize).withTraits(.italic)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2

        var attributes: [(NSRange, [NSAttributedString.Key: Any])] = []

        // 先把 `code` / **bold** / *italic* 替换成占位 token 再恢复（简单起见直接正则扫）
        // 先 inline code
        let ns = text as NSString
        var nsText = NSMutableString(string: text)
        var replacements: [(Range<String.Index>, String)] = []

        // inline code
        let codeRegex = try? NSRegularExpression(pattern: "`([^`]+)`")
        if let m = codeRegex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            for match in m.reversed() {
                let r = Range(match.range, in: text)!
                let inner = String(text[text.index(after: r.lowerBound)..<text.index(before: r.upperBound)])
                let repl = "\u{0001}CODE:\(inner)\u{0002}"
                nsText.replaceCharacters(in: match.range, with: repl)
            }
        }

        // bold
        let boldRegex = try? NSRegularExpression(pattern: "\\*\\*([^*]+)\\*\\*")
        if let m = boldRegex?.matches(in: nsText as String, range: NSRange(0..<nsText.length)) {
            for match in m.reversed() {
                let inner = (nsText as NSString).substring(with: NSRange(location: match.range.lowerBound + 2,
                                                                          length: match.range.length - 4))
                nsText.replaceCharacters(in: match.range, with: "\u{0001}BOLD:\(inner)\u{0002}")
            }
        }

        // italic
        let italicRegex = try? NSRegularExpression(pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)")
        if let m = italicRegex?.matches(in: nsText as String, range: NSRange(0..<nsText.length)) {
            for match in m.reversed() {
                let inner = (nsText as NSString).substring(with: NSRange(location: match.range.lowerBound + 1,
                                                                          length: match.range.length - 2))
                nsText.replaceCharacters(in: match.range, with: "\u{0001}ITALIC:\(inner)\u{0002}")
            }
        }

        // 分割占位符并输出
        let final = nsText as String
        let tokens = final.split(separator: "\u{0001}", omittingEmptySubsequences: false)
        for tok in tokens {
            let s = String(tok)
            if s.hasSuffix("\u{0002}") {
                let inner = String(s.dropLast())
                if inner.hasPrefix("CODE:") {
                    let content = String(inner.dropFirst(5))
                    out.append(NSAttributedString(
                        string: content,
                        attributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular),
                            .backgroundColor: NSColor.secondaryTextColor.withAlphaComponent(0.15),
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
                }
            } else {
                out.append(NSAttributedString(
                    string: s,
                    attributes: [.font: baseFont, .paragraphStyle: paragraph,
                                 .foregroundColor: NSColor.labelColor]
                ))
            }
        }
    }

    private func appendCodeBlock(_ out: NSMutableAttributedString, block: CodeBlock) {
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let background = NSColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1.0)
        let foreground = NSColor(red: 0.82, green: 0.86, blue: 0.92, alpha: 1.0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1

        // 顶部语言 tag
        out.append(NSAttributedString(
            string: "\n[ \(block.language.isEmpty ? "code" : block.language) ]\n",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor]
        ))
        // 代码体
        let full = block.body.hasSuffix("\n") ? block.body : block.body + "\n"
        out.append(NSAttributedString(
            string: full,
            attributes: [.font: mono,
                         .foregroundColor: foreground,
                         .backgroundColor: background,
                         .paragraphStyle: paragraph]
        ))
    }
}
