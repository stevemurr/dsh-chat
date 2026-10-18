import AppKit
import SwiftUI

@main
struct DSHChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.showSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(replacing: .newItem) {
                    Button("New Chat") { delegate.newChat() }
                        .keyboardShortcut("n", modifiers: .command)
                    Button("Show Chat") { delegate.controller.show() }
                        .keyboardShortcut("0", modifiers: .command)
                }
            }
    }
}

@MainActor
final class ChatPresentation: ObservableObject {
    @Published var showsSettings = false
    @Published var showsSidebar: Bool {
        didSet { defaults.set(showsSidebar, forKey: Self.sidebarKey) }
    }
    @Published var focusRequest = 0

    private let defaults: UserDefaults
    private static let sidebarKey = "chat.sidebarVisible"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsSidebar = defaults.object(forKey: Self.sidebarKey) as? Bool ?? true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let chat = ChatModel()
    let controller = NativeAppController()
    let presentation = ChatPresentation()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.configure(
            rootView: AnyView(ChatSurface(chat: chat, controller: controller, presentation: presentation)),
            onNewChat: { [weak self] in self?.newChat() },
            onSettings: { [weak self] in self?.showSettings() }
        )
        controller.show()
        chat.reconnect()
    }

    func newChat() {
        chat.newChat()
        presentation.focusRequest += 1
        controller.show()
    }

    func showSettings() {
        controller.show()
        presentation.showsSettings = true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.show()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !controller.isVisible { controller.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        chat.close()
        controller.tearDown()
    }
}
