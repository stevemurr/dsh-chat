import AppKit
import SwiftUI
import XCTest
@testable import DSHChat

@MainActor
final class NativeWindowLayoutTests: XCTestCase {
    /// Offscreen AppKit geometry check; no app activation, menu item or hotkey is installed.
    func testTrafficLightsShareHeaderCenterBeforeAndAfterNativeLayout() async throws {
        guard ProcessInfo.processInfo.environment["DSH_CHAT_NATIVE_LAYOUT_CHECK"] == "1" else {
            throw XCTSkip("Set DSH_CHAT_NATIVE_LAYOUT_CHECK=1 to check native window geometry")
        }
        let window = ChatPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        NativeWindowLayout.configureTitlebar(in: window)
        let content = NSHostingView(rootView: VStack(spacing: 0) {
            HStack {
                Button("Sidebar", action: {}).frame(width: 29, height: 28).padding(.leading, 86)
                Spacer()
                Button("Settings", action: {}).frame(width: 29, height: 28).padding(.trailing, 14)
            }
            .buttonStyle(.plain)
            .frame(height: NativeWindowLayout.toolbarHeight)
            Spacer()
        }.ignoresSafeArea(.container, edges: .top))
        window.contentView = content
        defer { window.contentView = nil }

        for size in [NSSize(width: 1000, height: 640), NSSize(width: 1200, height: 780),
                     NSSize(width: 860, height: 500), NSSize(width: 1000, height: 640)] {
            window.setContentSize(size)
            let frameView = try XCTUnwrap(content.superview)
            frameView.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            // Exercise the panel's normal update path, without manually applying
            // the alignment helper after AppKit has reset the native titlebar.
            window.update()
            for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                let button = try XCTUnwrap(window.standardWindowButton(kind))
                let container = try XCTUnwrap(button.superview)
                XCTAssertTrue(container.bounds.contains(button.frame), "Traffic light must fit its AppKit container")
                let frame = button.convert(button.bounds, to: nil)
                XCTAssertEqual(window.frame.height - frame.midY, NativeWindowLayout.toolbarHeight / 2,
                               accuracy: 0.25, "Native controls must share the SwiftUI header's vertical center")
                XCTAssertEqual(frame.midX, 24 + CGFloat(index) * 20, accuracy: 0.25)
                let hit = frameView.hitTest(frameView.convert(NSPoint(x: frame.midX, y: frame.midY), from: nil))
                XCTAssertTrue(hit === button || hit?.isDescendant(of: button) == true,
                              "Native controls must remain clickable at their displayed centers")
            }

            for x in [CGFloat(100.5), window.frame.width - 28.5] {
                let point = NSPoint(x: x, y: window.frame.height - NativeWindowLayout.toolbarHeight / 2)
                let hit = try XCTUnwrap(frameView.hitTest(frameView.convert(point, from: nil)))
                XCTAssertTrue(hit.isDescendant(of: content), "The native toolbar must let SwiftUI header controls receive clicks")
            }
        }
    }
}
