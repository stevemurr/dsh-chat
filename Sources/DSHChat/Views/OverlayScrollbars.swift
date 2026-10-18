import AppKit
import SwiftUI

extension View {
    /// Attach to the content inside a ScrollView so only that scroll view is configured.
    func overlayScrollbars() -> some View {
        background(OverlayScrollbarConfiguration().allowsHitTesting(false).accessibilityHidden(true))
    }
}

enum NativeOverlayScrollbars {
    static func configure(_ scrollView: NSScrollView) {
        // Native overlay scrollers provide translucent knobs and fade them after
        // scrolling without reserving a permanent strip beside the content.
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        scrollView.autohidesScrollers = true
        scrollView.scrollerKnobStyle = .default
        scrollView.drawsBackground = false
    }
}

private struct OverlayScrollbarConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollbarProbe { OverlayScrollbarProbe() }

    func updateNSView(_ view: OverlayScrollbarProbe, context: Context) {
        view.scheduleConfiguration()
    }
}

private final class OverlayScrollbarProbe: NSView {
    private var preferenceObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // AppKit updates every NSScrollView when the preference changes.
            // Reapply this app's presentation after that update has completed.
            self?.scheduleConfiguration()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleConfiguration()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleConfiguration()
    }

    func configureEnclosingScrollView() {
        guard let scrollView = enclosingScrollView else { return }
        NativeOverlayScrollbars.configure(scrollView)
    }

    func scheduleConfiguration() {
        configureEnclosingScrollView()
        // SwiftUI may still be assembling its native scroll hierarchy when the
        // probe is attached. Resolve it again at the end of the current update.
        DispatchQueue.main.async { [weak self] in self?.configureEnclosingScrollView() }
    }

    deinit {
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
    }
}
