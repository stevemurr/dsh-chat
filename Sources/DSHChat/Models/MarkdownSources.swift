import Foundation

struct MarkdownSource: Identifiable, Equatable {
    let title: String
    let url: URL
    let detail: String?

    init(title: String, url: URL, detail: String? = nil) {
        self.title = title
        self.url = url
        self.detail = detail
    }

    var id: String { Self.canonicalURL(url) }

    var host: String {
        let value = url.host?.lowercased() ?? ""
        return value.hasPrefix("www.") ? String(value.dropFirst(4)) : value
    }

    private static func canonicalURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if components.path.isEmpty { components.path = "/" }
        if (components.scheme == "https" && components.port == 443)
            || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        return components.string ?? url.absoluteString
    }
}

enum MarkdownSources {
    enum Part: Equatable {
        case block(MarkdownBlock)
        case sources([MarkdownSource])
    }

    struct Result: Equatable {
        let parts: [Part]

        var blocks: [MarkdownBlock] {
            parts.compactMap { if case .block(let block) = $0 { return block }; return nil }
        }

        var sources: [MarkdownSource] {
            parts.flatMap { if case .sources(let sources) = $0 { return sources }; return [] }
        }

        init(parts: [Part]) { self.parts = parts }

        init(blocks: [MarkdownBlock], sources: [MarkdownSource]) {
            parts = blocks.map(Part.block) + (sources.isEmpty ? [] : [.sources(sources)])
        }
    }

    /// Explicit source sections become chips in place. Linked list annotations
    /// stay available as source details; ordinary body and concluding prose stay
    /// in their original order.
    static func extract(from blocks: [MarkdownBlock], streaming: Bool = false) -> Result {
        if streaming { return extractStreaming(from: blocks) }
        var parts: [Part] = []
        var index = 0
        while index < blocks.count {
            guard let first = sourceSectionStart(blocks[index]),
                  let initialSources = sourceLinks(in: first, allowsDescription: true) else {
                parts.append(.block(blocks[index]))
                index += 1
                continue
            }

            var sources = initialSources
            var end = index + 1
            while end < blocks.count {
                let links = continuingSources(in: blocks[end], sourcesAreEmpty: sources.isEmpty, streaming: false)
                guard let links, !links.isEmpty else { break }
                sources.append(contentsOf: links)
                end += 1
            }

            if sources.isEmpty {
                parts.append(.block(blocks[index]))
                index += 1
            } else {
                parts.append(.sources(deduplicated(sources)))
                index = end
            }
        }
        return Result(parts: parts)
    }

    /// A source section is withheld until its links are complete. This keeps
    /// streamed Markdown syntax out of the answer without delaying body prose.
    private static func extractStreaming(from blocks: [MarkdownBlock]) -> Result {
        var parts: [Part] = []
        var index = 0
        while index < blocks.count {
            guard let first = streamingSectionStart(blocks[index]) else {
                if index != blocks.count - 1 || !isPendingSectionLabel(blocks[index]) {
                    parts.append(.block(blocks[index]))
                }
                index += 1
                continue
            }

            var sources = streamingLinks(in: first)
            var end = index + 1
            while end < blocks.count {
                // A new paragraph of body prose ends the source section.
                guard let links = continuingSources(in: blocks[end], sourcesAreEmpty: sources.isEmpty, streaming: true) else { break }
                sources.append(contentsOf: links)
                end += 1
            }
            if !sources.isEmpty { parts.append(.sources(deduplicated(sources))) }
            index = end
        }
        return Result(parts: parts)
    }

    /// Use the same source/prose boundary while streaming and after completion.
    /// An annotation is allowed on a source-list item or its first paragraph;
    /// later linked prose remains part of the answer in both renderings.
    private static func continuingSources(in block: MarkdownBlock, sourcesAreEmpty: Bool, streaming: Bool) -> [MarkdownSource]? {
        let raw: String
        let isListItem: Bool
        switch block {
        case .listItem(_, let text):
            raw = text
            isListItem = true
        case .paragraph(let text):
            raw = text
            isListItem = false
        default:
            return nil
        }

        let safeText = streaming ? completeLinkPrefix(in: raw).prefix : raw
        let inline = ChatMarkdown.inline(safeText)
        let allowsDescription = isListItem || (sourcesAreEmpty && startsWithLink(inline))
        let sources = sourceLinks(in: inline, allowsDescription: allowsDescription)
        if !streaming { return sources }
        if let sources, !sources.isEmpty { return sources }

        // Incomplete source syntax stays hidden, but an ordinary following list
        // item or paragraph can render immediately instead of appearing at finish.
        guard startsWithSourceSyntax(raw) || isPendingListMarker(raw) else { return nil }
        if !allowsDescription,
           let described = sourceLinks(in: inline, allowsDescription: true), !described.isEmpty {
            return nil
        }
        return streamingLinks(in: raw)
    }

    private static func streamingSectionStart(_ block: MarkdownBlock) -> String? {
        switch block {
        case .heading where sourceSectionStart(block) != nil:
            return ""
        case .paragraph(let text):
            // Accept an opening/closing emphasis marker while it is still being
            // streamed; its visible label is already unambiguous at the colon.
            guard let prefix = text.range(
                of: #"^\s*[*_`]*(?:sources|references|further\s+reading)\s*[*_`]*\s*:\s*[*_`]*\s*"#,
                options: [.regularExpression, .caseInsensitive]
            ) else { return nil }
            return String(text[prefix.upperBound...])
        default:
            return nil
        }
    }

    private static func isPendingSectionLabel(_ block: MarkdownBlock) -> Bool {
        let raw: String
        switch block {
        case .paragraph(let text), .heading(_, let text): raw = text
        default: return false
        }
        let label = raw
            .replacingOccurrences(of: #"^\s*#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return !label.isEmpty && ["sources", "references", "further reading"].contains { $0.hasPrefix(label) }
    }

    private static func startsWithSourceSyntax(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { "*_`".contains($0) })
        return trimmed.hasPrefix("[") || trimmed.hasPrefix("<")
    }

    private static func isPendingListMarker(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^(?:[-*+]|\d+[.)])$"#, options: .regularExpression) != nil
    }

    private static func streamingLinks(in raw: String) -> [MarkdownSource] {
        let scan = completeLinkPrefix(in: raw)
        let text = ChatMarkdown.inline(scan.prefix)
        if let sources = sourceLinks(in: text, allowsDescription: true) { return sources }
        // A later unsupported link must not remove earlier valid source chips.
        return scan.links.flatMap { sourceLinks(in: ChatMarkdown.inline($0), allowsDescription: false) ?? [] }
    }

    /// Foundation can normalize unfinished inline syntax. Find the last safe raw
    /// prefix first, respecting nested and escaped brackets/URL parentheses.
    private static func completeLinkPrefix(in raw: String) -> (prefix: String, links: [String]) {
        var index = raw.startIndex
        var links: [String] = []
        while index < raw.endIndex {
            if raw[index] == "\\" {
                index = raw.index(after: index)
                if index < raw.endIndex { index = raw.index(after: index) }
                continue
            }
            if raw[index] == "<" {
                guard let close = raw[index...].firstIndex(of: ">") else {
                    return (String(raw[..<index]), links)
                }
                index = raw.index(after: close)
                continue
            }
            guard raw[index] == "[" else {
                index = raw.index(after: index)
                continue
            }
            let start = index
            var brackets = 1
            index = raw.index(after: index)
            while index < raw.endIndex && brackets > 0 {
                if raw[index] == "\\" {
                    index = raw.index(after: index)
                    if index < raw.endIndex { index = raw.index(after: index) }
                    continue
                }
                if raw[index] == "[" { brackets += 1 }
                if raw[index] == "]" { brackets -= 1 }
                index = raw.index(after: index)
            }
            guard brackets == 0 else {
                return (String(raw[..<start]), links)
            }
            // A balanced literal annotation at the end is safe to retain. If it
            // is a new link label instead, it still has no URL and yields no chip.
            guard index < raw.endIndex else { return (raw, links) }
            guard raw[index] == "(" else { continue }
            var parentheses = 1
            var angleDestination = false
            var quotedTitle: Character?
            index = raw.index(after: index)
            while index < raw.endIndex && parentheses > 0 {
                if raw[index] == "\\" {
                    index = raw.index(after: index)
                    if index < raw.endIndex { index = raw.index(after: index) }
                    continue
                }
                if let quote = quotedTitle {
                    if raw[index] == quote { quotedTitle = nil }
                    index = raw.index(after: index)
                    continue
                }
                if parentheses == 1, !angleDestination,
                   raw[index] == "\"" || raw[index] == "'",
                   raw[raw.index(before: index)].isWhitespace {
                    quotedTitle = raw[index]
                    index = raw.index(after: index)
                    continue
                }
                if raw[index] == "<" { angleDestination = true }
                if raw[index] == ">" { angleDestination = false }
                if !angleDestination {
                    if raw[index] == "(" { parentheses += 1 }
                    if raw[index] == ")" { parentheses -= 1 }
                }
                index = raw.index(after: index)
            }
            guard parentheses == 0 else { return (String(raw[..<start]), links) }
            links.append(String(raw[start..<index]))
        }
        return (raw, links)
    }

    private static func startsWithLink(_ text: AttributedString) -> Bool {
        for run in text.runs where !String(text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return run.link != nil
        }
        return false
    }

    private static func deduplicated(_ sources: [MarkdownSource]) -> [MarkdownSource] {
        var result: [MarkdownSource] = []
        var positions: [String: Int] = [:]
        for source in sources {
            if let index = positions[source.id] {
                let first = result[index]
                let details = [first.detail, source.detail].compactMap { $0 }
                var unique: [String] = []
                for detail in details where !unique.contains(detail) {
                    unique.append(detail)
                }
                result[index] = MarkdownSource(
                    title: first.title, url: first.url,
                    detail: unique.isEmpty ? nil : unique.joined(separator: "\n")
                )
            } else {
                positions[source.id] = result.count
                result.append(source)
            }
        }
        return result
    }

    private static func sourceSectionStart(_ block: MarkdownBlock) -> AttributedString? {
        switch block {
        case .heading(_, let text):
            let label = String(ChatMarkdown.inline(text).characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return ["sources", "references", "further reading"].contains(label) ? AttributedString() : nil
        case .paragraph(let text):
            let inline = ChatMarkdown.inline(text)
            let visible = String(inline.characters)
            guard let prefix = visible.range(
                of: #"^\s*(?:sources|references|further\s+reading)\s*:\s*"#,
                options: [.regularExpression, .caseInsensitive]
            ) else { return nil }
            let count = visible.distance(from: visible.startIndex, to: prefix.upperBound)
            let start = inline.characters.index(inline.startIndex, offsetBy: count)
            return AttributedString(inline[start...])
        default:
            return nil
        }
    }

    private static func sourceLinks(in text: AttributedString, allowsDescription: Bool) -> [MarkdownSource]? {
        var sources: [MarkdownSource] = []
        var unlinked = ""
        var currentURL: URL?
        var currentTitle = ""

        func finishLink() {
            guard let url = currentURL else { return }
            let title = currentTitle.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            sources.append(MarkdownSource(title: title.isEmpty ? (url.host ?? url.absoluteString) : title, url: url))
            currentURL = nil
            currentTitle = ""
        }

        for run in text.runs {
            let value = String(text[run.range].characters)
            if let url = run.link {
                guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      !(url.host ?? "").isEmpty,
                      url.user == nil, url.password == nil else { return nil }
                if currentURL != url { finishLink() }
                currentURL = url
                currentTitle += value
            } else {
                finishLink()
                unlinked += value
            }
        }
        finishLink()

        // Finalized malformed links remain readable instead of losing their text.
        guard unlinked.range(of: #"\[[^\]]*\]\(|\[[^\]]*$"#, options: .regularExpression) == nil else { return nil }

        let remainder = unlinked.replacingOccurrences(of: #"\band\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let hasDescription = !remainder.unicodeScalars.allSatisfy { separators.contains($0) }
        guard !hasDescription || allowsDescription else { return nil }
        if hasDescription {
            let detail = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            sources = sources.map { MarkdownSource(title: $0.title, url: $0.url, detail: detail) }
        }
        return sources
    }
}
