import SwiftUI

struct ChatSettingsView: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject var controller: NativeAppController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("DSH Chat").font(.system(size: 18, weight: .semibold))
                    Text("A question away.").font(.system(size: 12)).foregroundStyle(ChatTheme.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(.bottom, 25)

            Text("KEYBOARD SHORTCUT").font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(ChatTheme.muted)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Show or hide chat").font(.system(size: 13, weight: .medium))
                    Text("Available from any app.").font(.system(size: 11)).foregroundStyle(ChatTheme.secondary)
                }
                Spacer()
                ShortcutRecorderView(controller: controller)
            }.padding(.vertical, 14)
            Divider().padding(.bottom, 20)

            Text("WINDOW").font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(ChatTheme.muted)
            Toggle(isOn: $controller.isPinned) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Keep chat open").font(.system(size: 13, weight: .medium))
                    Text("Leave the window visible when switching apps.").font(.system(size: 11)).foregroundStyle(ChatTheme.secondary)
                }
            }.toggleStyle(.switch).controlSize(.small).padding(.vertical, 14)
            Divider().padding(.bottom, 20)

            HStack {
                Text("LOCAL DSH HOST").font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(ChatTheme.muted)
                Spacer()
                Label(chat.isConnected ? "Connected" : "Disconnected", systemImage: chat.isConnected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11)).foregroundStyle(chat.isConnected ? ChatTheme.accent : ChatTheme.secondary)
            }.padding(.bottom, 10)
            Text("DSH Chat uses your local host’s models and tools. No folder or workspace is needed.")
                .font(.system(size: 12)).foregroundStyle(ChatTheme.secondary).lineSpacing(4)
            HStack {
                Text("Web search uses the tools available on your host.")
                    .font(.system(size: 11)).foregroundStyle(ChatTheme.muted)
                Spacer()
                Button(chat.isConnecting ? "Connecting…" : "Reconnect") { chat.reconnect() }
                    .disabled(chat.isConnecting || chat.isSubmitting || chat.isAnswering || chat.isStopping).controlSize(.small)
            }.padding(.top, 14)
            if !chat.isConnected {
                Text("Start DSH with its local bridge enabled. Connection details are discovered from DSH_HOME/mobile/dev-auth.json or ~/.dsh/mobile/dev-auth.json.")
                    .font(.system(size: 10)).foregroundStyle(ChatTheme.muted).lineSpacing(3).padding(.top, 12)
            }
        }
        .padding(25)
        .frame(width: 510)
        .foregroundStyle(ChatTheme.text)
        .background(ChatTheme.background)
        .tint(ChatTheme.accent)
        .onDisappear { controller.cancelShortcutRecording() }
    }
}
