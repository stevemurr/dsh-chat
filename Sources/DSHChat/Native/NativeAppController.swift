import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class NativeAppController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var shortcut: GlobalShortcut
    @Published private(set) var shortcutError: String?
    @Published private(set) var isRecordingShortcut = false
    @Published private(set) var isVisible = false
    @Published var isPinned: Bool {
        didSet { defaults.set(isPinned, forKey: "chat.windowPinned") }
    }

    private var panel: ChatPanel?
    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var previousApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var onNewChat: (() -> Void)?
    private var onSettings: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var nextHotKeyID: UInt32 = 0
    private var activeHotKeyID: UInt32 = 0
    private let defaults: UserDefaults
    private static let shortcutDefaultsKey = "chat.globalShortcut"
    private static let hotKeySignature: OSType = 0x44534843 // DSHC

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPinned = defaults.bool(forKey: "chat.windowPinned")
        if let data = defaults.data(forKey: Self.shortcutDefaultsKey),
           let saved = try? JSONDecoder().decode(GlobalShortcut.self, from: data), saved.isValid {
            shortcut = saved
        } else {
            shortcut = .defaultShortcut
        }
        super.init()
    }

    /// Call once after application launch. The same hosted view survives panel toggles.
    func configure(rootView: AnyView, onNewChat: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onNewChat = onNewChat
        self.onSettings = onSettings
        if let panel {
            (panel.contentView as? NSHostingView<AnyView>)?.rootView = rootView
            return
        }

        NSApp.setActivationPolicy(.regular)
        let panel = ChatPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.title = "DSH Chat"
        NativeWindowLayout.configureTitlebar(in: panel)
        panel.delegate = self
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.minSize = NSSize(width: 860, height: 500)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.setFrameAutosaveName("DSHChatPanel")
        panel.onHide = { [weak self] in self?.hide() }
        panel.isShortcutRecording = { [weak self] in self?.isRecordingShortcut == true }

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        self.panel = panel
        if panel.setFrameUsingName("DSHChatPanel") {
            if !defaults.bool(forKey: "chat.sidebarWindowSizeMigrated") {
                let width = max(panel.frame.width, 960)
                let frame = NSRect(x: panel.frame.minX, y: panel.frame.minY,
                                   width: width, height: panel.frame.height)
                panel.setFrame(frame, display: false)
            }
        } else {
            panel.center()
        }
        defaults.set(true, forKey: "chat.sidebarWindowSizeMigrated")
        positionWindowButtons()
        createStatusItem()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.previousApplication = application }
        }
        installHotKeyHandler()
        _ = registerShortcut(shortcut)
    }

    func show() {
        guard let panel else { return }
        if !panel.isVisible {
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApplication = frontmost
            }
            // Keep a restored window on a connected screen and place first launch near the top.
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }),
               let screen = NSScreen.main ?? NSScreen.screens.first {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                             y: frame.midY - panel.frame.height / 2 + 70))
            }
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeMain()
        panel.attachedSheet?.makeKeyAndOrderFront(nil)
        positionWindowButtons()
        isVisible = true
        updateStatusItem()
        NotificationCenter.default.post(name: .chatPanelDidShow, object: nil)
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        if isRecordingShortcut { cancelShortcutRecording() }
        let shouldRestore = NSApp.isActive
        panel.orderOut(nil)
        isVisible = false
        updateStatusItem()
        if shouldRestore, let previousApplication, !previousApplication.isTerminated {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    @discardableResult
    func updateShortcut(_ candidate: GlobalShortcut) -> Bool {
        guard candidate.isValid else {
            shortcutError = "Include Command, Option, or Control in your shortcut."
            return false
        }
        if candidate == shortcut, hotKey != nil {
            shortcutError = nil
            return true
        }
        guard registerShortcut(candidate) else { return false }
        shortcut = candidate
        if let data = try? JSONEncoder().encode(candidate) {
            defaults.set(data, forKey: Self.shortcutDefaultsKey)
        }
        updateStatusItem()
        return true
    }

    func resetShortcut() {
        if isRecordingShortcut { cancelShortcutRecording() }
        _ = updateShortcut(.defaultShortcut)
    }

    func beginShortcutRecording() {
        shortcutError = nil
        isRecordingShortcut = true
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    @discardableResult
    func finishShortcutRecording(_ candidate: GlobalShortcut) -> Bool {
        guard updateShortcut(candidate) else { return false }
        isRecordingShortcut = false
        return true
    }

    func cancelShortcutRecording() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        _ = registerShortcut(shortcut)
    }

    /// Releases registrations when an app delegate is shutting down explicitly.
    func tearDown() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    func windowDidResize(_ notification: Notification) { positionWindowButtons() }

    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible,
                  !self.isPinned, !self.isRecordingShortcut,
                  panel.attachedSheet == nil, !NSApp.isActive else { return }
            self.hide()
        }
    }

    private func positionWindowButtons() {
        guard let panel else { return }
        NativeWindowLayout.positionWindowButtons(in: panel)
    }

    private func installHotKeyHandler() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr else { return status }
                let controller = Unmanaged<NativeAppController>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated {
                    if identifier.signature == NativeAppController.hotKeySignature,
                       identifier.id == controller.activeHotKeyID {
                        controller.toggle()
                    }
                }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        )
        if status != noErr { shortcutError = "The keyboard shortcut service could not start (\(status))." }
    }

    private func registerShortcut(_ candidate: GlobalShortcut) -> Bool {
        guard eventHandler != nil else {
            shortcutError = "The keyboard shortcut service is unavailable. Restart DSH Chat to try again."
            return false
        }
        nextHotKeyID &+= 1
        let identifier = EventHotKeyID(signature: Self.hotKeySignature, id: nextHotKeyID)
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(candidate.keyCode, candidate.carbonModifiers,
            identifier, GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr, let replacement else {
            shortcutError = status == OSStatus(eventHotKeyExistsErr)
                ? "That shortcut is already in use. Choose another combination."
                : "That shortcut could not be registered. Try another combination (\(status))."
            return false
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        activeHotKeyID = identifier.id
        shortcutError = nil
        return true
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: "DSH Chat")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Show Chat", action: #selector(toggleFromMenu), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleMenuItem = toggle
        let newChat = NSMenuItem(title: "New Chat", action: #selector(newChatFromMenu), keyEquivalent: "n")
        newChat.target = self
        menu.addItem(newChat)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsFromMenu), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit DSH Chat", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        updateStatusItem()
    }

    private func updateStatusItem() {
        toggleMenuItem?.title = "\(isVisible ? "Hide" : "Show") Chat  \(shortcut.displayName)"
        statusItem?.button?.toolTip = "DSH Chat · \(shortcut.displayName)"
    }

    @objc private func toggleFromMenu() { toggle() }
    @objc private func newChatFromMenu() { onNewChat?(); show() }
    @objc private func settingsFromMenu() { onSettings?(); show() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }
}

@MainActor
enum NativeWindowLayout {
    static let toolbarHeight: CGFloat = 52

    static func configureTitlebar(in window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // A compact native toolbar gives the standard window controls enough
        // room to share the custom header's vertical center without clipping.
        window.toolbarStyle = .unifiedCompact
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "DSHChat.Titlebar")
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
        }
    }

    static func positionWindowButtons(in window: NSWindow) {
        guard window.contentView != nil else { return }
        for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(kind), let container = button.superview else { continue }
            let windowCenter = NSPoint(x: 24 + CGFloat(index) * 20,
                                       y: window.frame.height - toolbarHeight / 2)
            let center = container.convert(windowCenter, from: nil)
            button.setFrameOrigin(NSPoint(x: center.x - button.frame.width / 2,
                                          y: center.y - button.frame.height / 2))
        }
    }
}

final class ChatPanel: NSPanel {
    var onHide: (() -> Void)?
    var isShortcutRecording: (() -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        NativeWindowLayout.positionWindowButtons(in: self)
    }
    override func update() {
        super.update()
        // AppKit restores its standard positions during titlebar layout.
        NativeWindowLayout.positionWindowButtons(in: self)
    }
    override func cancelOperation(_ sender: Any?) { onHide?() }
    override func close() { onHide?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isShortcutRecording?() == true {
            return super.performKeyEquivalent(with: event)
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            onHide?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

extension Notification.Name {
    /// Focus the composer in response to the panel opening, if an overlay is not open.
    static let chatPanelDidShow = Notification.Name("DSHChat.panelDidShow")
}
