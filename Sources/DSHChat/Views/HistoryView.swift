import SwiftUI

struct HistoryView: View {
    @ObservedObject var chat: ChatModel
    let onSelect: () -> Void
    @State private var search = ""

    private var filtered: [ChatSummary] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return chat.history.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 18)

            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        Text(search.isEmpty ? "Recent" : "Search results")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ChatTheme.muted)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 5)

                        ForEach(filtered) { summary in
                            HistoryRow(summary: summary, isSelected: summary.id == chat.selectedSessionID, isBusy: chat.isBusy) {
                                if summary.id != chat.selectedSessionID {
                                    chat.openChat(id: summary.id)
                                }
                                onSelect()
                            }
                            .contextMenu {
                                Button("Remove from History", role: .destructive) { chat.deleteChat(id: summary.id) }
                                    .disabled(chat.isBusy)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 14)
                    .overlayScrollbars()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(ChatTheme.text)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chat history")
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ChatTheme.muted)
            TextField("Search chats", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .accessibilityLabel("Search chats")
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ChatTheme.muted)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(ChatTheme.composer, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(ChatTheme.border))
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(ChatTheme.muted)
                .padding(.bottom, 3)
            Text(search.isEmpty ? "No chats yet" : "No matching chats")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChatTheme.secondary)
            Text(search.isEmpty ? "Your conversations will appear here." : "Try a different search.")
                .font(.system(size: 11))
                .foregroundStyle(ChatTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 25)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryRow: View {
    let summary: ChatSummary
    let isSelected: Bool
    let isBusy: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? ChatTheme.accent : ChatTheme.muted)
                    .frame(width: 14)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.title)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? ChatTheme.text : ChatTheme.secondary)
                        .lineLimit(1)
                    Text(summary.updatedAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(ChatTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? ChatTheme.selection : isHovered && !isBusy ? ChatTheme.hover : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { isHovered = $0 }
        .help(summary.title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
