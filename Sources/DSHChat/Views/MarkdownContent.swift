import AppKit
import SwiftUI

enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(Int, String)
    case quote(String)
    case listItem(String, String)
    case code(String, String)
    case table([String], [[String]])
    case rule
}

enum ChatMarkdown {
    static func blocks(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var result: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0
        func flush() {
            if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let fence = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index]); index += 1
                }
                result.append(.code(language, code.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flush()
            } else if index + 1 < lines.count, line.contains("|"), isTableDivider(lines[index + 1]) {
                flush()
                let header = cells(line)
                var rows: [[String]] = []
                index += 2
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(cells(lines[index])); index += 1
                }
                result.append(.table(header, rows))
                continue
            } else if ["---", "***", "___"].contains(trimmed) {
                flush(); result.append(.rule)
            } else if trimmed.hasPrefix("#"), let space = trimmed.firstIndex(of: " "), trimmed[..<space].allSatisfy({ $0 == "#" }), trimmed.distance(from: trimmed.startIndex, to: space) <= 6 {
                flush()
                result.append(.heading(trimmed.distance(from: trimmed.startIndex, to: space), String(trimmed[trimmed.index(after: space)...])))
            } else if trimmed.hasPrefix("> ") {
                flush(); result.append(.quote(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flush(); result.append(.listItem("•", String(trimmed.dropFirst(2))))
            } else if let match = trimmed.range(of: #"^\d+[.)] "#, options: .regularExpression) {
                flush()
                result.append(.listItem(String(trimmed[match]).trimmingCharacters(in: .whitespaces), String(trimmed[match.upperBound...])))
            } else {
                paragraph.append(line)
            }
            index += 1
        }
        flush()
        return result
    }

    private static func cells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableDivider(_ line: String) -> Bool {
        let values = cells(line)
        return !values.isEmpty && values.allSatisfy { cell in
            let dashes = cell.replacingOccurrences(of: ":", with: "")
            return dashes.count >= 3 && dashes.allSatisfy { $0 == "-" }
        }
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

struct MarkdownContent: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(ChatMarkdown.blocks(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .font(.system(size: 16))
        .foregroundStyle(ChatTheme.text)
        .lineSpacing(5)
        .textSelection(.enabled)
        .tint(ChatTheme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            guard ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
            return .systemAction
        })
    }

    @ViewBuilder private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(ChatMarkdown.inline(text)).frame(maxWidth: .infinity, alignment: .leading)
        case .heading(let level, let text):
            Text(ChatMarkdown.inline(text))
                .font(.system(size: level == 1 ? 24 : level == 2 ? 20 : 18, weight: .semibold))
                .foregroundStyle(ChatTheme.text).padding(.top, 5)
        case .quote(let text):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1).fill(ChatTheme.accent.opacity(0.4)).frame(width: 2)
                Text(ChatMarkdown.inline(text)).foregroundStyle(ChatTheme.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        case .listItem(let marker, let text):
            HStack(alignment: .top, spacing: 9) {
                Text(marker).foregroundStyle(ChatTheme.secondary).frame(minWidth: 14, alignment: .trailing)
                Text(ChatMarkdown.inline(text)).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .code(let language, let code):
            CodeBlock(language: language, code: code)
        case .table(let headers, let rows):
            MarkdownTable(headers: headers, rows: rows)
        case .rule:
            Divider().overlay(ChatTheme.border).padding(.vertical, 3)
        }
    }
}

private struct CodeBlock: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "Code" : language)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(ChatTheme.muted)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12)).foregroundStyle(ChatTheme.secondary)
                }.buttonStyle(.plain)
            }.padding(.horizontal, 12).padding(.vertical, 8)
            Divider().overlay(ChatTheme.border)
            ScrollView(.horizontal) {
                Text(code).font(.system(size: 14, design: .monospaced))
                    .lineSpacing(5).padding(15).fixedSize(horizontal: true, vertical: true)
                    .overlayScrollbars()
            }
        }
        .background(ChatTheme.codeBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ChatTheme.border))
    }
}
