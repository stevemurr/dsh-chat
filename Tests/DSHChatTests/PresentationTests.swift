import AppKit
import DSHKit
import DSHProtocol
import SwiftUI
import XCTest
@testable import DSHChat

@MainActor
final class PresentationTests: XCTestCase {
    func testSidebarPreferencePersistsAndSurvivesConversationChanges() async throws {
        let fixture = try makeFixture()
        defer { fixture.chat.close(); fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let presentation = ChatPresentation(defaults: fixture.defaults)
        XCTAssertTrue(presentation.showsSidebar)

        fixture.chat.openChat(id: "quantum")
        try await waitUntil { fixture.chat.isConnected }
        XCTAssertTrue(presentation.showsSidebar)
        XCTAssertEqual(fixture.chat.timeline.items.count, 2)
        fixture.chat.newChat()
        XCTAssertTrue(presentation.showsSidebar)
        XCTAssertNil(fixture.chat.selectedSessionID)

        presentation.showsSidebar = false
        XCTAssertFalse(ChatPresentation(defaults: fixture.defaults).showsSidebar)
        fixture.chat.openChat(id: "day-trips")
        try await waitUntil { fixture.chat.isConnected }
        XCTAssertFalse(presentation.showsSidebar)
        presentation.showsSidebar = true
        XCTAssertTrue(ChatPresentation(defaults: fixture.defaults).showsSidebar)
        let calls = await fixture.transport.calledEndpoints
        XCTAssertEqual(Set(calls), ["session/modelCatalog"], "Opening history must not create or mutate a host session")
    }

    /// An opt-in native rendering check. The transcript and catalog are supplied
    /// by an in-memory transport; no desktop window or global hotkey is installed.
    func testRenderNativeSurface() async throws {
        guard let destination = ProcessInfo.processInfo.environment["DSH_CHAT_PREVIEW_PATH"] else {
            throw XCTSkip("Set DSH_CHAT_PREVIEW_PATH to render native previews")
        }
        let fixture = try makeFixture()
        defer { fixture.chat.close(); fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.chat.openChat(id: "quantum")
        try await waitUntil { fixture.chat.isConnected }
        XCTAssertEqual(fixture.chat.history.count, 3)
        XCTAssertEqual(fixture.chat.selectedSessionID, "quantum")
        XCTAssertEqual(fixture.chat.timeline.items.count, 2)
        XCTAssertEqual(fixture.chat.modelName, "Nemotron Lightning")
        XCTAssertFalse(fixture.chat.isBusy)

        let controller = NativeAppController(defaults: fixture.defaults)
        let presentation = ChatPresentation(defaults: fixture.defaults)
        let baseURL = URL(fileURLWithPath: destination)
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (suffix, size, sidebar, pinned) in [
                ("", NSSize(width: 1000, height: 640), true, false),
                ("-collapsed", NSSize(width: 780, height: 640), false, false),
                ("-pinned", NSSize(width: 1000, height: 640), true, true),
                ("-wide", NSSize(width: 1400, height: 840), true, false),
                ("-wide-collapsed", NSSize(width: 1400, height: 840), false, false),
                ("-minimum", NSSize(width: 860, height: 500), true, false),
            ] {
                presentation.showsSidebar = sidebar
                controller.isPinned = pinned
                let url = previewURL(baseURL, suffix: suffix + "-" + mode)
                try await render(chat: fixture.chat, controller: controller, presentation: presentation,
                                 size: size, appearance: appearance, to: url)
            }
            let settings = ChatSettingsView(chat: fixture.chat, controller: controller)
            try await renderView(settings, size: NSSize(width: 510, height: 510), appearance: appearance,
                                 to: previewURL(baseURL, suffix: "-settings-" + mode))
            let markdown = MarkdownContent(text: PreviewTransport.answer)
                .padding(30).frame(width: 760).background(ChatTheme.background)
            try await renderView(markdown, size: NSSize(width: 760, height: 1100), appearance: appearance,
                                 to: previewURL(baseURL, suffix: "-markdown-" + mode))
        }
        XCTAssertTrue(presentation.showsSidebar)
        fixture.chat.newChat()
        XCTAssertTrue(presentation.showsSidebar, "Starting a chat must keep the sidebar open")
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            try await render(chat: fixture.chat, controller: controller, presentation: presentation,
                             size: NSSize(width: 860, height: 500), appearance: appearance,
                             to: previewURL(baseURL, suffix: "-empty-minimum-" + mode))
        }
        let calls = await fixture.transport.calledEndpoints
        XCTAssertEqual(calls, ["session/modelCatalog"], "Rendering must only read the fake model catalog")
    }

    /// Exercise an appearance change on the same native view hierarchy. Rebuilding
    /// the surface for each mode would miss colors that become stuck after launch.
    func testNativeSurfaceFollowsAppearanceChanges() async throws {
        guard ProcessInfo.processInfo.environment["DSH_CHAT_NATIVE_LAYOUT_CHECK"] == "1"
                || ProcessInfo.processInfo.environment["DSH_CHAT_PREVIEW_PATH"] != nil else {
            throw XCTSkip("Enable native layout checks or previews to check live appearance changes")
        }
        let fixture = try makeFixture()
        defer { fixture.chat.close(); fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.chat.draft = "A readable follow-up question."
        let controller = NativeAppController(defaults: fixture.defaults)
        let presentation = ChatPresentation(defaults: fixture.defaults)
        let surface = ChatSurface(chat: fixture.chat, controller: controller, presentation: presentation)
        let (window, view) = makeWindow(surface, size: NSSize(width: 1000, height: 640))
        defer { window.contentView = nil }

        var backgroundLuminances: [Double] = []
        var textLuminances: [Double] = []
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
            window.appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            try await settle(window: window, view: view)
            XCTAssertEqual(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), appearanceName,
                           "The hosted surface must inherit the window's appearance")
            let material = try XCTUnwrap(descendants(of: view).compactMap { $0 as? NSVisualEffectView }.first)
            XCTAssertNil(material.appearance, "The panel material must inherit appearance instead of forcing a mode")
            XCTAssertEqual(material.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), appearanceName)
            let editor = try XCTUnwrap(descendants(of: view).compactMap { $0 as? PromptTextView }.first)
            XCTAssertEqual(editor.textColor, NSColor.labelColor, "Native input text must use a dynamic semantic color")
            XCTAssertEqual(editor.insertionPointColor, NSColor.labelColor)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(editor.font).pointSize, 16)
            textLuminances.append(try luminance(of: XCTUnwrap(editor.textColor), appearance: editor.effectiveAppearance))
            let bitmap = try bitmap(window: window, view: view)
            backgroundLuminances.append(try backgroundLuminance(bitmap))
        }
        XCTAssertGreaterThan(backgroundLuminances[0] - backgroundLuminances[1], 0.45,
                             "The rendered panel must visibly switch from light to dark")
        XCTAssertEqual(backgroundLuminances[0], backgroundLuminances[2], accuracy: 0.02,
                       "Returning to light appearance must update the existing surface")
        XCTAssertGreaterThan(textLuminances[1] - textLuminances[0], 0.5,
                             "Input text must switch contrast with its background")
        XCTAssertEqual(textLuminances[0], textLuminances[2], accuracy: 0.01)

        let body = NSHostingView(rootView: MarkdownContent(text: "A readable answer.").frame(width: 400))
        XCTAssertGreaterThanOrEqual(body.fittingSize.height, 18,
                                   "A normal Markdown line must retain a comfortable reading size")
        XCTAssertFalse(window.isVisible)
    }

    private func render(chat: ChatModel, controller: NativeAppController, presentation: ChatPresentation,
                        size: NSSize, appearance: NSAppearance.Name, to destination: URL) async throws {
        let (window, view) = makeWindow(ChatSurface(chat: chat, controller: controller, presentation: presentation), size: size)
        window.appearance = try XCTUnwrap(NSAppearance(named: appearance))
        defer { window.contentView = nil }
        try await settle(window: window, view: view)

        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(view.bounds.width, size.width, accuracy: 0.5)
        XCTAssertEqual(view.bounds.height, size.height, accuracy: 0.5)
        let editor = try XCTUnwrap(descendants(of: view).compactMap { $0 as? PromptTextView }.first)
        let composer = try XCTUnwrap(editor.enclosingScrollView)
        let composerFrame = composer.convert(composer.bounds, to: view)
        XCTAssertTrue(view.bounds.contains(composerFrame), "Composer must remain entirely inside the window")
        XCTAssertGreaterThan(composerFrame.width, 500, "Sidebar must leave enough room for the conversation")
        XCTAssertGreaterThan(composerFrame.minX, presentation.showsSidebar ? 232 : 0, "Composer must not overlap the sidebar")
        XCTAssertGreaterThanOrEqual(composerFrame.height, 50)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(editor.font).pointSize, 16)
        let scrollViews = descendants(of: view).compactMap { $0 as? NSScrollView }
        for scrollView in scrollViews {
            XCTAssertEqual(scrollView.scrollerStyle, .overlay,
                           "Chat scrollbars must overlay content without reserving a permanent gutter")
            XCTAssertTrue(scrollView.autohidesScrollers,
                          "Chat scrollbars must disappear when scrolling stops")
        }
        if !chat.timeline.items.isEmpty {
            // Code and table scroll views fill the actual rendered Markdown row,
            // so their native frames reveal a hidden centered-width constraint.
            let markdownScrollViews = scrollViews.filter {
                $0.hasHorizontalScroller && !$0.hasVerticalScroller && $0.bounds.width > 500
            }
            XCTAssertGreaterThanOrEqual(markdownScrollViews.count, 2,
                                        "The sample answer must expose both its code block and table")
            let paneMinX: CGFloat = presentation.showsSidebar ? 233 : 0
            let expectedWidth = size.width - paneMinX - 60
            for scrollView in markdownScrollViews {
                let frame = scrollView.convert(scrollView.bounds, to: view)
                XCTAssertEqual(frame.minX, paneMinX + 30, accuracy: 1,
                               "Answer text must align to the conversation pane's left inset")
                XCTAssertEqual(frame.width, expectedWidth, accuracy: 1,
                               "Rendered answers must use the pane width, including in wide windows")
            }
        }
        try write(try bitmap(window: window, view: view), size: size, to: destination)
    }

    private func renderView<Content: View>(_ content: Content, size: NSSize, appearance: NSAppearance.Name,
                                           to destination: URL) async throws {
        // Settings and Markdown samples have no chat toolbar. A borderless panel
        // avoids reserving native titlebar space around their fixed-size canvas.
        let view = NSHostingView(rootView: content
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(ChatTheme.background))
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = try XCTUnwrap(NSAppearance(named: appearance))
        window.contentView = view
        defer { window.contentView = nil }
        try await settle(window: window, view: view)
        try write(try bitmap(window: window, view: view), size: size, to: destination)
    }

    private func makeWindow<Content: View>(_ content: Content, size: NSSize) -> (NSPanel, NSHostingView<Content>) {
        let view = NSHostingView(rootView: content)
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        NativeWindowLayout.configureTitlebar(in: window)
        window.contentView = view
        return (window, view)
    }

    private func settle(window: NSWindow, view: NSView) async throws {
        view.layoutSubtreeIfNeeded()
        // Let SwiftUI process native appearance and layout changes offscreen.
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
        view.superview?.layoutSubtreeIfNeeded()
        NativeWindowLayout.positionWindowButtons(in: window)
        window.displayIfNeeded()
    }

    private func bitmap(window: NSWindow, view: NSView) throws -> NSBitmapImageRep {
        let frame = try XCTUnwrap(view.superview)
        let bitmap = try XCTUnwrap(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        return bitmap
    }

    private func write(_ bitmap: NSBitmapImageRep, size: NSSize, to destination: URL) throws {
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: destination)
        let scale = CGFloat(bitmap.pixelsWide) / size.width
        XCTAssertGreaterThanOrEqual(scale, 1)
        XCTAssertEqual(CGFloat(bitmap.pixelsHigh), size.height * scale, accuracy: 1)
    }

    private func previewURL(_ baseURL: URL, suffix: String) -> URL {
        baseURL.deletingLastPathComponent()
            .appendingPathComponent(baseURL.deletingPathExtension().lastPathComponent + suffix)
            .appendingPathExtension(baseURL.pathExtension)
    }

    private func backgroundLuminance(_ bitmap: NSBitmapImageRep) throws -> Double {
        let x = Int(Double(bitmap.pixelsWide) * 0.80)
        let y = Int(Double(bitmap.pixelsHigh) * 0.04)
        let colors = try (-2...2).flatMap { dx in
            try (-2...2).map { dy in try XCTUnwrap(bitmap.colorAt(x: x + dx, y: y + dy)) }
        }
        return try colors.map { try luminance(of: $0, appearance: nil) }.reduce(0, +) / Double(colors.count)
    }

    private func luminance(of color: NSColor, appearance: NSAppearance?) throws -> Double {
        var resolved: NSColor?
        if let appearance {
            appearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) }
        } else { resolved = color.usingColorSpace(.sRGB) }
        let rgb = try XCTUnwrap(resolved)
        func linear(_ value: CGFloat) -> Double {
            let component = Double(value)
            return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func makeFixture() throws -> (chat: ChatModel, transport: PreviewTransport, defaults: UserDefaults, suiteName: String) {
        let suiteName = "DSHChatPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let now = Date()
        let summaries = [
            ChatSummary(id: "quantum", title: "Quantum computing explained with analogy", updatedAt: now, hostIdentity: "preview://dsh", modelID: "preview/nemotron"),
            ChatSummary(id: "day-trips", title: "Weekend day trips near San Francisco", updatedAt: now.addingTimeInterval(-3600), hostIdentity: "preview://dsh", modelID: nil),
            ChatSummary(id: "dinner", title: "A simple weeknight dinner", updatedAt: now.addingTimeInterval(-86400), hostIdentity: "preview://dsh", modelID: nil),
        ]
        defaults.set(try JSONEncoder().encode(summaries), forKey: "DSHChat.history.v1")
        let transport = PreviewTransport()
        let chat = ChatModel(connection: PreviewConnection(transport: transport), defaults: defaults)
        return (chat, transport, defaults, suiteName)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        let limit = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > limit { XCTFail("Timed out waiting for preview state"); throw PreviewError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct PreviewConnection: DSHConnecting {
    let transport: PreviewTransport
    func connected() async throws -> DSHConnectedClient {
        .init(client: DSHClient(transport: transport), identity: "preview://dsh")
    }
    func disconnect() async {}
}

private enum PreviewError: Error { case timeout, unexpectedEndpoint(String) }

private actor PreviewTransport: DSHTransport {
    private(set) var calledEndpoints: [String] = []
    private var continuations: [AsyncThrowingStream<JSONValue, any Error>.Continuation] = []

    func call(_ endpoint: String, args: RemoteArgs) async throws -> JSONValue? {
        calledEndpoints.append(endpoint)
        guard endpoint == "session/modelCatalog" else { throw PreviewError.unexpectedEndpoint(endpoint) }
        return ["default": ["provider": "preview", "model": "nemotron"], "groups": [
            ["id": "preview", "name": "Preview", "models": [["id": "nemotron", "name": "Nemotron Lightning"]]],
        ]]
    }

    func stream(_ endpoint: String, args: RemoteArgs) async throws -> AsyncThrowingStream<JSONValue, any Error> {
        let (stream, continuation) = AsyncThrowingStream<JSONValue, any Error>.makeStream()
        continuations.append(continuation)
        switch endpoint {
        case "$events": continuation.yield(["type": "ready", "clientId": "preview-client"])
        case "session/follow": continuation.yield(Self.snapshot)
        default: throw PreviewError.unexpectedEndpoint(endpoint)
        }
        return stream
    }

    static let answer = """
        # Quantum Computing Explained with a Simple Analogy

        ## The Spinning Coin Analogy

        **Classical bit:** Like a static coin that is either heads (0) or tails (1). When you look at it, it has one definite value.

        **Qubit (quantum bit):** Imagine a spinning coin. Before you measure it, a qubit can be in a superposition of both states. Measurement produces a single result: 0 or 1.

        ## Why This Matters

        Quantum algorithms carefully combine these possibilities so useful answers become more likely. The spinning coin is only an analogy, but it gives you a place to start.

        > The analogy explains the idea, but a real qubit follows the mathematics of quantum mechanics.

        - A **bit** has one definite value.
        - A **qubit** can be prepared in a combination of states.

        ```swift
        let outcomes = ["heads", "tails"]
        print(outcomes.randomElement()!)
        ```

        | Idea | Classical bit | Qubit |
        | --- | --- | --- |
        | State | Zero or one | Superposition |
        | Measurement | Reads a value | Produces one result |

        Read more about [quantum information](https://www.ibm.com/quantum).
        """

    private static var snapshot: JSONValue {
        return ["type": "snapshot", "header": [:], "cursor": 4, "hasMore": false,
            "projections": ["values": ["title": "Quantum computing explained with analogy"]],
            "records": [
                record("user/message", seq: 1, data: ["source": ["kind": "user"], "content": [["type": "text", "text": "Explain quantum computing with a simple analogy."]]]),
                record("turn/start", seq: 2, data: ["turn": 1]),
                record("assistant/message", seq: 3, data: ["message": ["content": [["type": "text", "text": .string(answer)]]]]),
                record("turn/end", seq: 4, data: ["turn": 1]),
            ],
        ]
    }

    private static func record(_ type: String, seq: Int, data: JSONValue) -> JSONValue {
        ["type": "event", "event": ["type": .string(type), "seq": .number(Double(seq)), "time": 1_700_000_000_000, "data": data]]
    }
}
