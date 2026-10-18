import AppKit
import SwiftUI

/// Records one shortcut while temporarily suspending the existing global shortcut.
struct ShortcutRecorderView: View {
    @ObservedObject var controller: NativeAppController

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Button {
                    if controller.isRecordingShortcut {
                        controller.cancelShortcutRecording()
                    } else {
                        controller.beginShortcutRecording()
                    }
                } label: {
                    Text(controller.isRecordingShortcut ? "Press shortcut…" : controller.shortcut.displayName)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .frame(minWidth: 120)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Record global keyboard shortcut")
                .accessibilityValue(controller.isRecordingShortcut ? "Recording" : controller.shortcut.displayName)

                Button(controller.isRecordingShortcut ? "Cancel" : "Reset") {
                    if controller.isRecordingShortcut {
                        controller.cancelShortcutRecording()
                    } else {
                        controller.resetShortcut()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(ChatTheme.secondary)
            }

            if let error = controller.shortcutError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(ChatTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(controller.isRecordingShortcut
                     ? "Press a key with ⌘, ⌥, or ⌃. Escape cancels."
                     : "Show or hide DSH Chat from any app.")
                    .font(.caption)
                    .foregroundStyle(ChatTheme.secondary)
            }
        }
        .background {
            ShortcutCaptureView(isRecording: controller.isRecordingShortcut) { event in
                if event.keyCode == 53 {
                    controller.cancelShortcutRecording()
                } else {
                    _ = controller.finishShortcutRecording(GlobalShortcut(event: event))
                }
            }
            .frame(width: 0, height: 0)
        }
        .onDisappear { controller.cancelShortcutRecording() }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    var isRecording: Bool
    var onKey: (NSEvent) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onKey = onKey
        view.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async { [weak view] in
                guard let view, view.isRecording else { return }
                view.window?.makeFirstResponder(view)
            }
        } else if view.window?.firstResponder === view {
            view.window?.makeFirstResponder(nil)
        }
    }

    final class CaptureView: NSView {
        var isRecording = false
        var onKey: ((NSEvent) -> Void)?
        override var acceptsFirstResponder: Bool { isRecording }
        override func keyDown(with event: NSEvent) {
            if isRecording { onKey?(event) } else { super.keyDown(with: event) }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording else { return super.performKeyEquivalent(with: event) }
            onKey?(event)
            return true
        }
        override func cancelOperation(_ sender: Any?) {
            // Escape is delivered through keyDown while recording.
        }
    }
}
