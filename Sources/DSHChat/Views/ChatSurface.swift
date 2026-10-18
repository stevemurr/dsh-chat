import AppKit
import DSHSession
import SwiftUI

struct ChatSurface: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject var controller: NativeAppController
    @ObservedObject var presentation: ChatPresentation
    @State private var followsBottom = true

    private var hasConversation: Bool {
        !chat.timeline.items.isEmpty || chat.pendingPrompt != nil || chat.isBusy
    }

    private var hasRunningToolCard: Bool {
        chat.timeline.running && chat.timeline.items.contains { item in
            guard item.turn == chat.timeline.currentTurn,
                  case .tool(let tool) = item.content else { return false }
            return tool.isRunning
        }
    }

    private var showsActivityCard: Bool {
        guard chat.isBusy, !hasRunningToolCard,
              chat.timeline.live?.text.isEmpty ?? true else { return false }
        if chat.pendingPrompt == nil, let last = chat.timeline.items.last,
           last.turn == chat.timeline.currentTurn, case .assistant = last.content {
            // The answer can commit before turn/end. Keep its presentation
            // steady rather than inserting a new Thinking card for that gap.
            return false
        }
        return true
    }

    private var transcriptMessages: [TranscriptMessage] {
        let identities = chat.timeline.answerIds
        var messages = chat.timeline.items.map { item in
            TranscriptMessage(item: TimelineItem(
                id: identities.committed[item.id] ?? item.id,
                seq: item.seq, time: item.time, content: item.content, turn: item.turn
            ))
        }
        if let pending = chat.pendingPrompt {
            messages.append(TranscriptMessage(item: TimelineItem(
                id: "pending-user", seq: chat.timeline.cursor + 1, time: .distantPast,
                content: .user(text: pending, imageCount: 0), turn: chat.timeline.currentTurn
            )))
        }
        if let live = chat.timeline.live, !live.text.isEmpty {
            messages.append(TranscriptMessage(item: TimelineItem(
                id: identities.live, seq: chat.timeline.cursor + 1, time: .distantPast,
                content: .assistant(markdown: live.text), turn: chat.timeline.currentTurn
            ), streaming: true))
        }
        return messages
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(ChatTheme.border).frame(height: 1)

            HStack(spacing: 0) {
                if presentation.showsSidebar {
                    HistoryView(chat: chat) {
                        presentation.focusRequest += 1
                    }
                    .frame(width: 232)
                    .frame(maxHeight: .infinity)
                    .background(ChatTheme.sidebar)
                    Rectangle().fill(ChatTheme.border).frame(width: 1)
                }

                chatContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            ZStack {
                PanelMaterial()
                ChatTheme.background.opacity(0.94)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(ChatTheme.border))
        .ignoresSafeArea(.container, edges: .top)
        .tint(ChatTheme.accent)
        .sheet(isPresented: $presentation.showsSettings) {
            ChatSettingsView(chat: chat, controller: controller)
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            if let error = chat.errorMessage {
                errorBanner(error)
            }
            if let error = controller.shortcutError, !controller.isRecordingShortcut {
                HStack(spacing: 9) {
                    Image(systemName: "keyboard").foregroundStyle(ChatTheme.secondary)
                    Text(error).font(.system(size: 11)).foregroundStyle(ChatTheme.secondary)
                    Spacer()
                    Button("Change Shortcut") { presentation.showsSettings = true }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(ChatTheme.accent)
                }
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(ChatTheme.surface)
            }

            if hasConversation {
                transcript
            } else {
                welcome
            }

            if !chat.approvals.isEmpty || !chat.questions.isEmpty {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(chat.approvals) { approval in
                            ApprovalCard(approval: approval, isAnswering: chat.isAnswering) { outcome in
                                chat.answer(approval, outcome: outcome)
                            }
                        }
                        ForEach(chat.questions) { request in
                            QuestionCard(request: request, isAnswering: chat.isAnswering) { selections, custom in
                                chat.answer(request, selections: selections, custom: custom)
                            }
                        }
                    }.padding(.horizontal, 24).padding(.vertical, 10)
                        .overlayScrollbars()
                }.frame(maxHeight: 240)
            }

            composer
            footer
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            if presentation.showsSidebar {
                HStack(spacing: 8) {
                    sidebarToggle
                    Text("Chats")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ChatTheme.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 86)
                .padding(.trailing, 12)
                .frame(width: 232, height: NativeWindowLayout.toolbarHeight)
                .background(ChatTheme.sidebar)
                Rectangle().fill(ChatTheme.border).frame(width: 1)
                detailToolbar
            } else {
                detailToolbar
                    .overlay(alignment: .leading) {
                        sidebarToggle.padding(.leading, 86)
                    }
            }
        }
        .frame(height: NativeWindowLayout.toolbarHeight)
    }

    private var sidebarToggle: some View {
        IconButton(symbol: "sidebar.left", label: presentation.showsSidebar ? "Hide sidebar (⇧⌘H)" : "Show sidebar (⇧⌘H)") {
            presentation.showsSidebar.toggle()
            if !presentation.showsSidebar { presentation.focusRequest += 1 }
        }
        .keyboardShortcut("h", modifiers: [.command, .shift])
        .accessibilityValue(presentation.showsSidebar ? "Expanded" : "Collapsed")
    }

    private var detailToolbar: some View {
        ZStack {
            Text(chat.currentTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChatTheme.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.leading, presentation.showsSidebar ? 104 : 130)
                .padding(.trailing, presentation.showsSidebar ? 104 : 130)
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                IconButton(symbol: controller.isPinned ? "pin.fill" : "pin", label: controller.isPinned ? "Unpin window" : "Keep window open", selected: controller.isPinned) {
                    controller.isPinned.toggle()
                }
                IconButton(symbol: "square.and.pencil", label: "New chat (⌘N)") { startNewChat() }
                    .disabled(!chat.canStartNewChat)
                    .keyboardShortcut("n", modifiers: .command)
                IconButton(symbol: "gearshape", label: "Settings (⌘,)") { presentation.showsSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
            .padding(.trailing, 15)
        }
        .frame(maxWidth: .infinity)
        .frame(height: NativeWindowLayout.toolbarHeight)
    }

    private var welcome: some View {
        GeometryReader { geometry in
            welcomeContent(compact: geometry.size.height < 360)
        }
    }

    private func welcomeContent(compact: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: compact ? 12 : 24)
            BrandMark(size: compact ? 38 : 52)
                .padding(.bottom, compact ? 14 : 21)
            Text("What’s on your mind?")
                .font(.system(size: compact ? 22 : 25, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(ChatTheme.text)
            Text("A quick question. A fresh perspective. A place to think.")
                .font(.system(size: 13))
                .foregroundStyle(ChatTheme.secondary)
                .padding(.top, 9)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                suggestion("globe", title: "Explore the web", detail: "Find a fresh perspective", prompt: "What are some interesting science discoveries this week?", compact: compact)
                suggestion("lightbulb", title: "Understand something", detail: "Make the complex feel simple", prompt: "Explain quantum computing with a simple analogy.", compact: compact)
                suggestion("arrow.triangle.branch", title: "Weigh the options", detail: "See it from both sides", prompt: "Help me compare two options: ", compact: compact)
                suggestion("text.alignleft", title: "Find the right words", detail: "Get a thought into shape", prompt: "Help me write a short, thoughtful message about ", compact: compact)
            }
            .frame(maxWidth: 482)
            .padding(.top, compact ? 20 : 30)
            Spacer(minLength: compact ? 12 : 24)
        }
        .padding(.horizontal, compact ? 24 : 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func suggestion(_ icon: String, title: String, detail: String, prompt: String, compact: Bool) -> some View {
        Button {
            chat.draft = prompt
            presentation.focusRequest += 1
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(ChatTheme.secondary)
                    .frame(width: 17).padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(ChatTheme.text)
                    if !compact { Text(detail).font(.system(size: 11)).foregroundStyle(ChatTheme.muted) }
                }
                Spacer(minLength: 0)
            }
            .padding(compact ? 10 : 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ChatTheme.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ChatTheme.border))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(SuggestionButtonStyle())
    }

    private var transcript: some View {
        let messages = transcriptMessages
        let items = messages.map(\.item)
        return ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(messages.enumerated()), id: \.element.item.id) { index, message in
                        TimelineRow(item: message.item, cleanUserText: chat.cleanedUserText,
                                    streaming: message.streaming)
                            .padding(.top, rowSpacing(before: index, in: items))
                    }
                    if showsActivityCard {
                        ActivityCard(title: chat.connectionLabel,
                                     symbol: chat.isSearching ? "globe" : "ellipsis.bubble",
                                     status: .running,
                                     expandable: !(chat.timeline.live?.reasoning.isEmpty ?? true)) {
                            if let reasoning = chat.timeline.live?.reasoning {
                                Text(reasoning).font(.system(size: 14))
                                    .foregroundStyle(ChatTheme.secondary)
                                    .lineSpacing(5).textSelection(.enabled)
                            }
                        }
                        .padding(.top, trailingRowSpacing())
                    }
                    // Keep the gap inside the scroll target so following new
                    // activity leaves breathing room above the composer.
                    Color.clear.frame(height: 24).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlayScrollbars()
                .padding(.horizontal, 30)
                .padding(.top, 26)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 100
            } action: { _, value in followsBottom = value }
            .onChange(of: chat.timeline.items.count) { _, _ in
                if followsBottom { reader.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: chat.timeline.live?.text) { _, _ in
                if followsBottom { reader.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: chat.timeline.live?.reasoning) { _, _ in
                if followsBottom { reader.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: chat.pendingPrompt) { _, value in
                if value != nil { followsBottom = true; reader.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: chat.selectedSessionID) { _, _ in
                followsBottom = true
                reader.scrollTo("bottom", anchor: .bottom)
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    private func rowSpacing(before index: Int, in items: [TimelineItem]) -> CGFloat {
        guard index > 0 else { return 0 }
        return items[index - 1].content.isActivityCard && items[index].content.isActivityCard ? 12 : 28
    }

    private func trailingRowSpacing() -> CGFloat {
        if chat.pendingPrompt != nil { return 28 }
        guard let previous = chat.timeline.items.last else { return 0 }
        return previous.content.isActivityCard ? 12 : 28
    }

    private var composer: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                if chat.draft.isEmpty {
                    Text(hasConversation ? "Ask a follow-up…" : "Ask anything…")
                        .font(.system(size: 16))
                        .foregroundStyle(ChatTheme.muted)
                        .padding(.top, 3)
                        .allowsHitTesting(false)
                }
                ComposerTextView(text: $chat.draft, focusRequest: presentation.focusRequest) {
                    if chat.canSend { chat.send() }
                }
            }.frame(height: 51)

            HStack(spacing: 11) {
                Button {
                    chat.webSearchEnabled.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "globe").font(.system(size: 12))
                        Text("Web search").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(chat.webSearchEnabled ? ChatTheme.accent : ChatTheme.muted)
                    .padding(.horizontal, 8).frame(height: 25)
                    .background(chat.webSearchEnabled ? ChatTheme.accent.opacity(0.09) : ChatTheme.surface, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(chat.webSearchEnabled ? "Use the host’s web tools when helpful" : "Ask without web search")
                .accessibilityValue(chat.webSearchEnabled ? "On" : "Off")
                .disabled(chat.isBusy)

                Menu {
                    if chat.modelOptions.isEmpty { Text("Connect to DSH to load models") }
                    ForEach(chat.modelOptions) { option in
                        Button {
                            chat.selectModel(id: option.id)
                        } label: {
                            if chat.selectedModelID == option.id {
                                Label(option.name, systemImage: "checkmark")
                            } else { Text(option.name) }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(chat.modelName).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: 11)).foregroundStyle(ChatTheme.secondary)
                    .frame(maxWidth: 235, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(ChatTheme.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(chat.isBusy)
                .help("Choose a model")

                Spacer(minLength: 4)
                if chat.isBusy {
                    Button { chat.stop() } label: {
                        Image(systemName: "stop.fill").font(.system(size: 10))
                            .foregroundStyle(ChatTheme.text)
                            .frame(width: 29, height: 27)
                            .background(ChatTheme.selection, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain).disabled(!chat.canStop)
                    .help("Stop response").accessibilityLabel("Stop response")
                } else {
                    Button { chat.send() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(chat.canSend ? ChatTheme.sendForeground : ChatTheme.disabledForeground)
                            .frame(width: 29, height: 27)
                            .background(chat.canSend ? ChatTheme.accent : ChatTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain).disabled(!chat.canSend)
                    .help("Send message (↵)").accessibilityLabel("Send message")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 10)
        .background(ChatTheme.composer, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(ChatTheme.border))
        .padding(.horizontal, 20)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(chat.isConnected ? Color(nsColor: .systemGreen) : ChatTheme.muted).frame(width: 4, height: 4)
            Text(chat.connectionLabel).font(.system(size: 10)).foregroundStyle(ChatTheme.muted)
            Spacer()
            KeyCap(text: "⇧ ↵")
            Text("new line").font(.system(size: 10)).foregroundStyle(ChatTheme.muted)
            ChatTheme.border.frame(width: 1, height: 10).padding(.horizontal, 5)
            KeyCap(text: "esc")
            Text("hide").font(.system(size: 10)).foregroundStyle(ChatTheme.muted)
        }
        .padding(.horizontal, 24)
        .frame(height: 35)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(ChatTheme.warning)
            Text(text).font(.system(size: 11)).foregroundStyle(ChatTheme.secondary).lineLimit(3)
            Spacer(minLength: 5)
            Button("Reconnect") { chat.reconnect() }
                .font(.system(size: 11, weight: .medium)).buttonStyle(.plain).foregroundStyle(ChatTheme.accent)
                .disabled(chat.isConnecting)
        }
        .padding(.horizontal, 22).padding(.vertical, 11)
        .background(ChatTheme.warning.opacity(0.06))
    }

    private func startNewChat() {
        chat.newChat()
        presentation.focusRequest += 1
    }
}

private struct TranscriptMessage {
    let item: TimelineItem
    var streaming = false
}

private struct SuggestionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? ChatTheme.hover : .clear, in: RoundedRectangle(cornerRadius: 9))
    }
}
