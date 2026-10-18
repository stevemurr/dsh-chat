import AppKit
import SwiftUI

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        NativeOverlayScrollbars.configure(scroll)
        let editor = PromptTextView()
        editor.isRichText = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 16)
        editor.updateAppearanceColors()
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainerInset = NSSize(width: 0, height: 3)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.onSubmit = onSubmit
        editor.setAccessibilityLabel("Message")
        editor.setAccessibilityHelp("Return to send. Shift Return for a new line.")
        scroll.documentView = editor
        context.coordinator.editor = editor
        context.coordinator.observeFocus()
        context.coordinator.observeScrollerStyle(scroll)
        DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        NativeOverlayScrollbars.configure(scroll)
        guard let editor = scroll.documentView as? PromptTextView else { return }
        editor.onSubmit = onSubmit
        if editor.string != text {
            editor.string = text
            editor.updateAppearanceColors()
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var editor: NSTextView?
        var lastFocusRequest: Int
        var focusObserver: NSObjectProtocol?
        var scrollerStyleObserver: NSObjectProtocol?

        init(_ parent: ComposerTextView) {
            self.parent = parent
            lastFocusRequest = parent.focusRequest
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func observeFocus() {
            focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
                guard let editor = self?.editor, let window = note.object as? NSWindow,
                      window == editor.window, window.attachedSheet == nil else { return }
                // Keep selection when revisiting an existing prompt.
                window.makeFirstResponder(editor)
            }
        }

        func observeScrollerStyle(_ scrollView: NSScrollView) {
            scrollerStyleObserver = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak scrollView] _ in
                DispatchQueue.main.async {
                    if let scrollView { NativeOverlayScrollbars.configure(scrollView) }
                }
            }
        }

        deinit {
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
            if let scrollerStyleObserver { NotificationCenter.default.removeObserver(scrollerStyleObserver) }
        }
    }
}

final class PromptTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceColors()
    }

    func updateAppearanceColors() {
        // Keep semantic colors in the text storage and typing attributes so an
        // open composer follows appearance changes without replacing its text.
        textColor = .labelColor
        insertionPointColor = .labelColor
        var attributes = typingAttributes
        attributes[.foregroundColor] = NSColor.labelColor
        attributes[.font] = font ?? NSFont.systemFont(ofSize: 16)
        typingAttributes = attributes
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, !hasMarkedText() {
            window?.performClose(nil)
            return
        }
        if (event.keyCode == 36 || event.keyCode == 76), !event.modifierFlags.contains(.shift), !hasMarkedText() {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }
}
