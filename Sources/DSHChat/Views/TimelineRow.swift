import AppKit
import DSHSession
import SwiftUI

extension TimelineContent {
    var isActivityCard: Bool {
        switch self {
        case .reasoning, .tool: true
        default: false
        }
    }
}

struct MessageRow: View {
    let isUser: Bool
    let text: String
    var streaming = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if isUser {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 21)).foregroundStyle(ChatTheme.muted)
                        .frame(width: 24, height: 24)
                } else { BrandMark(size: 24) }
                Text(isUser ? "You" : "DSH")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isUser ? ChatTheme.secondary : ChatTheme.accent)
                Spacer()
                if !isUser && !streaming {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12)).foregroundStyle(ChatTheme.muted)
                    }.buttonStyle(.plain).help(copied ? "Copied" : "Copy response")
                }
            }
            if isUser {
                Text(text).font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ChatTheme.text).lineSpacing(5)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            } else { MarkdownContent(text: text) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TimelineRow: View {
    let item: TimelineItem
    let cleanUserText: (String) -> String

    var body: some View {
        switch item.content {
        case .user(let text, let imageCount):
            VStack(alignment: .leading, spacing: 6) {
                MessageRow(isUser: true, text: cleanUserText(text))
                if imageCount > 0 {
                    Label("\(imageCount) attached image\(imageCount == 1 ? "" : "s")", systemImage: "photo")
                        .font(.system(size: 12)).foregroundStyle(ChatTheme.muted)
                }
            }
        case .assistant(let markdown):
            MessageRow(isUser: false, text: markdown)
        case .tool(let tool):
            ToolRow(tool: tool)
        case .reasoning(let text):
            ActivityCard(title: "Thinking", symbol: "ellipsis.bubble", status: .complete) {
                Text(text).font(.system(size: 14)).foregroundStyle(ChatTheme.secondary)
                    .lineSpacing(5).textSelection(.enabled)
            }
        case .notice(let text, let isError):
            Label(text, systemImage: isError ? "exclamationmark.circle" : "info.circle")
                .font(.system(size: 14)).foregroundStyle(isError ? ChatTheme.warning : ChatTheme.secondary)
                .textSelection(.enabled)
        case .subagent(let label, _):
            Label(label, systemImage: "bubble.left.and.bubble.right").font(.system(size: 13)).foregroundStyle(ChatTheme.secondary)
        case .command(let name, let output, let isError):
            DisclosureGroup {
                if let output {
                    Text(output).font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(ChatTheme.secondary).lineSpacing(4).textSelection(.enabled)
                }
            } label: {
                Label(name, systemImage: isError ? "exclamationmark.circle" : "terminal")
                    .font(.system(size: 13)).foregroundStyle(ChatTheme.secondary)
            }
        }
    }
}

private struct ToolRow: View {
    let tool: ToolCallItem
    private var activity: ToolActivity { ToolActivity(toolName: tool.name) }

    var body: some View {
        ActivityCard(title: label, symbol: icon,
                     status: tool.isRunning ? .running : tool.result?.isError == true ? .failed : .complete) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tool.summary).font(.system(size: 14)).foregroundStyle(ChatTheme.secondary)
                    .lineSpacing(5).textSelection(.enabled)
                if let result = tool.result {
                    Text(String(result.text.prefix(12000))).font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(result.isError ? ChatTheme.warning : ChatTheme.secondary)
                        .lineSpacing(4).textSelection(.enabled)
                }
            }
        }
    }

    private var icon: String {
        activity.symbol
    }

    private var label: String {
        if tool.result?.isError == true {
            switch activity {
            case .webSearch: return "Web search failed"
            case .webFetch: return "Page could not be read"
            default: return tool.name
            }
        }
        switch activity {
        case .webSearch: return tool.isRunning ? "Searching the web" : "Searched the web"
        case .webFetch: return tool.isRunning ? "Reading a page" : "Read a page"
        default: return tool.name
        }
    }
}
