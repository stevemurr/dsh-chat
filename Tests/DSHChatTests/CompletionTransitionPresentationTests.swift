import AppKit
import DSHKit
import DSHProtocol
import SwiftUI
import XCTest
@testable import DSHChat

@MainActor
final class CompletionTransitionPresentationTests: XCTestCase {
    /// Keep a native child view as a witness: recreating the completed answer
    /// destroys its code scroller even when the rendered text is unchanged.
    func testCompletedAnswerKeepsItsNativeViewAndScrollPosition() async throws {
        guard ProcessInfo.processInfo.environment["DSH_CHAT_NATIVE_LAYOUT_CHECK"] == "1" else {
            throw XCTSkip("Enable native layout checks to inspect response completion")
        }

        for endsBeforeCommit in [false, true] {
            let suiteName = "DSHChatCompletion.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            let summary = ChatSummary(id: "completion", title: "Response completion",
                                      updatedAt: .distantPast, hostIdentity: "preview://completion", modelID: nil)
            defaults.set(try JSONEncoder().encode([summary]), forKey: "DSHChat.history.v1")
            let transport = CompletionTransport()
            let chat = ChatModel(connection: CompletionConnection(transport: transport), defaults: defaults)
            defer { chat.close(); defaults.removePersistentDomain(forName: suiteName) }
            chat.openChat(id: summary.id)
            try await waitUntil { chat.isConnected && chat.timeline.running }

            let presentation = ChatPresentation(defaults: defaults)
            presentation.showsSidebar = false
            let controller = NativeAppController(defaults: defaults)
            let view = NSHostingView(rootView: ChatSurface(chat: chat, controller: controller,
                                                          presentation: presentation))
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
                                 styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                 backing: .buffered, defer: false)
            NativeWindowLayout.configureTitlebar(in: window)
            window.contentView = view
            defer { window.contentView = nil }

            await transport.emit(Self.streamStart)
            await transport.emit(Self.streamChunk)
            try await waitUntil { chat.timeline.live?.text == Self.answer }
            try await settle(window: window, view: view)
            let code = try codeScroller(in: view)
            let transcript = try XCTUnwrap(enclosingTranscript(of: code))
            let initialFrame = code.convert(code.bounds, to: view)
            let initialOffset = transcript.contentView.bounds.origin
            let initialHeight = try XCTUnwrap(transcript.documentView).bounds.height

            if endsBeforeCommit {
                await transport.emit(Self.streamEnd)
                try await settle(window: window, view: view)
                assertPreserved(code: code, transcript: transcript, frame: initialFrame,
                                offset: initialOffset, height: initialHeight, view: view,
                                stage: "stream end before durable message")
            }

            await transport.emit(Self.record("assistant/message", seq: 3, data: [
                "message": ["content": [["type": "text", "text": .string(Self.answer)]]],
            ]))
            try await waitUntil { chat.timeline.items.count == 2 }
            try await settle(window: window, view: view)
            assertPreserved(code: code, transcript: transcript, frame: initialFrame,
                            offset: initialOffset, height: initialHeight, view: view,
                            stage: "durable message while turn is finishing")

            if !endsBeforeCommit { await transport.emit(Self.streamEnd) }
            await transport.emit(Self.record("turn/end", seq: 4, data: ["turn": 1]))
            try await waitUntil { !chat.isBusy }
            try await settle(window: window, view: view)
            assertPreserved(code: code, transcript: transcript, frame: initialFrame,
                            offset: initialOffset, height: initialHeight, view: view,
                            stage: "completed turn")
            XCTAssertFalse(window.isVisible)
        }
    }

    private func assertPreserved(code: NSScrollView, transcript: NSScrollView, frame: NSRect,
                                 offset: NSPoint, height: CGFloat, view: NSView, stage: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let current = try? codeScroller(in: view)
        XCTAssertTrue(current === code, "Answer remounted at \(stage)", file: file, line: line)
        guard let current else { return }
        let currentFrame = current.convert(current.bounds, to: view)
        XCTAssertEqual(currentFrame.minY, frame.minY, accuracy: 1,
                       "Answer shifted at \(stage)", file: file, line: line)
        XCTAssertEqual(currentFrame.height, frame.height, accuracy: 1, file: file, line: line)
        XCTAssertEqual(transcript.contentView.bounds.origin.y, offset.y, accuracy: 1,
                       "Scroll position jumped at \(stage)", file: file, line: line)
        XCTAssertEqual(transcript.documentView?.bounds.height ?? 0, height, accuracy: 1,
                       "Completion inserted or removed transcript content at \(stage)", file: file, line: line)
    }

    private func codeScroller(in view: NSView) throws -> NSScrollView {
        try XCTUnwrap(descendants(of: view).compactMap { $0 as? NSScrollView }.first {
            $0.hasHorizontalScroller && !$0.hasVerticalScroller
        })
    }

    private func enclosingTranscript(of view: NSView) -> NSScrollView? {
        var parent = view.superview
        while let current = parent {
            if let scrollView = current as? NSScrollView { return scrollView }
            parent = current.superview
        }
        return nil
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func settle(window: NSWindow, view: NSView) async throws {
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > deadline { throw CompletionError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    nonisolated fileprivate static func record(_ type: String, seq: Int, data: JSONValue) -> JSONValue {
        ["type": "event", "event": ["type": .string(type), "seq": .number(Double(seq)),
                                    "time": 1_700_000_000_000, "data": data]]
    }

    private static let streamStart: JSONValue = ["type": "assistant-stream", "frame": [
        "type": "start", "attemptId": "completion", "turn": 1, "step": 1,
    ]]
    private static let streamChunk: JSONValue = ["type": "assistant-stream", "frame": [
        "type": "chunk", "attemptId": "completion", "index": 0,
        "chunk": ["type": "text-delta", "index": 0, "text": .string(answer)],
    ]]
    private static let streamEnd: JSONValue = ["type": "assistant-stream", "frame": [
        "type": "end", "attemptId": "completion", "outcome": ["seq": 3],
    ]]

    private static let answer = """
    ## A response with sources

    This answer has enough text to make the conversation scroll. Its presentation should stay in place when the server finishes sending it.

    A second paragraph gives the answer a little more height. The completion transition should preserve the same native views, source chips, and scroll position.

    A third paragraph explains why the native child view is useful for this check. The response can look identical in two screenshots while still disappearing between them.

    A fourth paragraph keeps the answer taller than the visible transcript, so inserting a temporary thinking card would move the visible response.

    ```swift
    let answer = "Preserve the rendered answer"
    print(answer)
    ```

    Sources: [Reference guide](https://docs.example.com/guide), [Background article](https://news.example.com/background).
    """
}

private struct CompletionConnection: DSHConnecting {
    let transport: CompletionTransport
    func connected() async throws -> DSHConnectedClient {
        .init(client: DSHClient(transport: transport), identity: "preview://completion")
    }
    func disconnect() async {}
}

private enum CompletionError: Error { case timeout, unexpectedEndpoint(String) }

private actor CompletionTransport: DSHTransport {
    private var follow: AsyncThrowingStream<JSONValue, any Error>.Continuation?
    private var events: AsyncThrowingStream<JSONValue, any Error>.Continuation?

    func call(_ endpoint: String, args: RemoteArgs) async throws -> JSONValue? {
        guard endpoint == "session/modelCatalog" else { throw CompletionError.unexpectedEndpoint(endpoint) }
        return ["groups": []]
    }

    func stream(_ endpoint: String, args: RemoteArgs) async throws -> AsyncThrowingStream<JSONValue, any Error> {
        let (stream, continuation) = AsyncThrowingStream<JSONValue, any Error>.makeStream()
        switch endpoint {
        case "$events":
            events = continuation
            continuation.yield(["type": "ready", "clientId": "completion-client"])
        case "session/follow":
            follow = continuation
            continuation.yield(["type": "snapshot", "header": [:], "cursor": 2, "hasMore": false,
                                "projections": [:], "records": [
                CompletionTransitionPresentationTests.record("user/message", seq: 1, data: [
                    "source": ["kind": "user"], "content": [["type": "text", "text": "Explain this topic."]],
                ]),
                CompletionTransitionPresentationTests.record("turn/start", seq: 2, data: ["turn": 1]),
            ]])
        default: throw CompletionError.unexpectedEndpoint(endpoint)
        }
        return stream
    }

    func emit(_ value: JSONValue) { follow?.yield(value) }
}
