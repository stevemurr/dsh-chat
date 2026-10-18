import AppKit
import SwiftUI
import XCTest
@testable import DSHChat

@MainActor
final class SourceChipsPresentationTests: XCTestCase {
    /// Sources use synthetic URLs and offscreen windows, so this does not open
    /// a browser, load website images, or connect to the chat host.
    func testSourceChipsWrapWithinTheAnswerWidth() async throws {
        guard nativeChecksEnabled else {
            throw XCTSkip("Enable native layout checks or source previews to inspect source chips")
        }

        var heights: [CGFloat] = []
        for width in [CGFloat(340), 720, 1200] {
            let (window, view) = makeWindow(SourceChips(sources: Self.sources), width: width)
            defer { window.contentView = nil }
            try await settle(window: window, view: view)

            let marker = try XCTUnwrap(descendants(of: view).compactMap { $0 as? SourceBoundsView }.first)
            let frame = marker.convert(marker.bounds, to: view)
            XCTAssertEqual(frame.minX, 20, accuracy: 0.5)
            XCTAssertEqual(frame.width, width - 40, accuracy: 0.5,
                           "The source stack must use the answer width without extending past it")
            XCTAssertTrue(view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                          "All wrapped source rows must remain inside the native host")
            XCTAssertGreaterThanOrEqual(frame.height, 34,
                                        "Sources must retain a readable chip height")
            heights.append(frame.height)
            XCTAssertFalse(window.isVisible)
        }

        XCTAssertGreaterThan(heights[0], heights[2] + 68,
                             "Narrow answers must move source chips onto additional rows")
        XCTAssertGreaterThanOrEqual(heights[1], heights[2],
                                    "Widening an answer must not create extra source rows")
    }

    func testRenderSourcesInLightAndDarkAppearance() async throws {
        guard let destination = ProcessInfo.processInfo.environment["DSH_CHAT_SOURCES_PREVIEW_PATH"] else {
            throw XCTSkip("Set DSH_CHAT_SOURCES_PREVIEW_PATH to render native source previews")
        }
        let annotatedDocument = MarkdownSources.extract(from: ChatMarkdown.blocks(Self.annotatedAnswer))
        XCTAssertEqual(annotatedDocument.sources.count, 3,
                       "Annotated source bullets must become three website chips")
        XCTAssertEqual(annotatedDocument.blocks.last, .paragraph(Self.closingParagraph),
                       "A conclusion containing an ordinary link must remain visible")
        let sourceIndex = try XCTUnwrap(annotatedDocument.parts.firstIndex {
            if case .sources = $0 { return true }
            return false
        })
        let conclusionIndex = try XCTUnwrap(annotatedDocument.parts.firstIndex {
            $0 == .block(.paragraph(Self.closingParagraph))
        })
        XCTAssertLessThan(sourceIndex, conclusionIndex,
                          "Website chips must stay before the conclusion instead of moving to the answer footer")

        let baseURL = URL(fileURLWithPath: destination)
        for (fixture, answer) in [("", Self.answer), ("-annotated", Self.annotatedAnswer)] {
            for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                for width in [CGFloat(340), 720, 1200] {
                    let (window, view) = makeWindow(MarkdownContent(text: answer), width: width)
                    defer { window.contentView = nil }
                    window.appearance = try XCTUnwrap(NSAppearance(named: appearance))
                    try await settle(window: window, view: view)

                    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let url = previewURL(baseURL, suffix: "\(fixture)-\(Int(width))-\(mode)")
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
                    XCTAssertEqual(view.bounds.width, width, accuracy: 0.5)
                    XCTAssertFalse(window.isVisible)
                }
            }
        }
    }

    func testStreamingSourcesNeverExposeIncompleteMarkdown() async throws {
        guard nativeChecksEnabled else {
            throw XCTSkip("Enable native layout checks or source previews to inspect streaming source chips")
        }

        for width in [CGFloat(340), 720] {
            var heights: [CGFloat] = []
            for answer in [Self.streamingBody, Self.partialSourceLabel, Self.partialSourceLink,
                           Self.oneCompleteSource, Self.oneSourceWithPendingLink] {
                let (window, view) = makeWindow(
                    MessageRow(isUser: false, text: answer, streaming: true), width: width)
                defer { window.contentView = nil }
                try await settle(window: window, view: view)

                let marker = try XCTUnwrap(descendants(of: view).compactMap { $0 as? SourceBoundsView }.first)
                heights.append(marker.bounds.height)
                XCTAssertFalse(window.isVisible)
            }

            XCTAssertEqual(heights[0], heights[1], accuracy: 0.5,
                           "A partial Sources label must not briefly appear as answer text")
            XCTAssertEqual(heights[0], heights[2], accuracy: 0.5,
                           "An unfinished source link must remain hidden until it can become a chip")
            XCTAssertGreaterThan(heights[3], heights[0] + 30,
                                 "A complete source must appear as a readable chip while the answer streams")
            XCTAssertEqual(heights[3], heights[4], accuracy: 0.5,
                           "The next incomplete source must not add a temporary text row below existing chips")
        }
    }

    func testRenderStreamingSourceStagesInLightAndDarkAppearance() async throws {
        guard let destination = ProcessInfo.processInfo.environment["DSH_CHAT_SOURCES_PREVIEW_PATH"] else {
            throw XCTSkip("Set DSH_CHAT_SOURCES_PREVIEW_PATH to render streaming source previews")
        }

        let baseURL = URL(fileURLWithPath: destination)
        let stages = [("pending", Self.partialSourceLink),
                      ("one-source", Self.oneSourceWithPendingLink),
                      ("complete", Self.completedStreamingAnswer)]
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (stage, answer) in stages {
                let (window, view) = makeWindow(
                    MessageRow(isUser: false, text: answer, streaming: true), width: 720)
                defer { window.contentView = nil }
                window.appearance = try XCTUnwrap(NSAppearance(named: appearance))
                try await settle(window: window, view: view)

                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let url = previewURL(baseURL, suffix: "-streaming-\(stage)-\(mode)")
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
                XCTAssertFalse(window.isVisible)
            }
        }
    }

    private var nativeChecksEnabled: Bool {
        ProcessInfo.processInfo.environment["DSH_CHAT_NATIVE_LAYOUT_CHECK"] == "1"
            || ProcessInfo.processInfo.environment["DSH_CHAT_SOURCES_PREVIEW_PATH"] != nil
    }

    private func makeWindow<Content: View>(_ content: Content, width: CGFloat) -> (NSPanel, NSHostingView<some View>) {
        let view = NSHostingView(rootView: content
            .frame(width: width - 40, alignment: .leading)
            .background(SourceBoundsMarker())
            .padding(20)
            .frame(width: width, alignment: .topLeading)
            .background(ChatTheme.background))
        let size = NSSize(width: width, height: ceil(view.fittingSize.height))
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        return (window, view)
    }

    private func settle(window: NSWindow, view: NSView) async throws {
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func previewURL(_ baseURL: URL, suffix: String) -> URL {
        baseURL.deletingLastPathComponent()
            .appendingPathComponent(baseURL.deletingPathExtension().lastPathComponent + suffix)
            .appendingPathExtension(baseURL.pathExtension)
    }

    private static let sources: [MarkdownSource] = [
        ("A detailed introduction to the topic and its background", "https://news.example.com/background"),
        ("Developer documentation and reference material", "https://docs.example.com/reference"),
        ("An overview of the terminology", "https://reference.example.com/overview"),
        ("Community discussion with additional context", "https://forums.example.com/discussion"),
        ("A video explaining the main ideas", "https://video.example.com/explainer"),
        ("An unusually long article title that should appear in the tooltip rather than make the website chip excessively wide", "https://a-very-long-website-address-for-checking-narrow-source-chips.example.com/article"),
    ].map { MarkdownSource(title: $0.0, url: URL(string: $0.1)!) }

    private static var answer: String {
        let links = sources.map { "[\($0.title)](\($0.url.absoluteString))" }.joined(separator: ", ")
        return """
        ## A quick answer with sources

        Here is the explanation in a readable paragraph. The [documentation](https://docs.example.com/guide) link stays alongside the point it supports.

        - **Background:** A few sources give useful context for the answer.
        - **Details:** Website chips below collect the references into a compact stack.

        Sources: \(links), [Repeated reference](https://news.example.com/background#details).
        """
    }

    private static let closingParagraph = "For the latest event information, check the [organizer's guide](https://organizer.example.com/guide) before making plans."

    private static let streamingBody = "Here is the answer, with references collected below as website chips."
    private static let partialSourceLabel = streamingBody + "\n\n**Sou"
    private static let partialSourceLink = streamingBody + "\n\n**Sources:**\n\n- [Background article"
    private static let oneCompleteSource = streamingBody + "\n\n**Sources:**\n\n- [Background article](https://news.example.com/background)"
    private static let oneSourceWithPendingLink = oneCompleteSource + "\n- [Developer reference](https://docs.example"
    private static let completedStreamingAnswer = oneCompleteSource + "\n- [Developer reference](https://docs.example.com/reference)\n- [Community discussion](https://forums.example.com/discussion)\n\n" + closingParagraph

    private static var annotatedAnswer: String {
        """
        Based on the web search, here is a local car event:

        ## Community Car Show

        - **Location:** Community museum grounds.
        - **Details:** A gathering featuring classic and modern cars.
        - **Registration:** Check the organizer's website for participation details.

        **Sources:**

        - [Car Events List](https://events.example.com/car-show) — Community Car Show · Event overview and venue information.
        - [Community Car Show](https://organizer.example.com/car-show) — Registration and visitor information from the organizer.
        - [Event details](https://community.example.com/car-show) — Community announcement with additional information about the show.

        \(closingParagraph)
        """
    }
}

private struct SourceBoundsMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> SourceBoundsView { SourceBoundsView() }
    func updateNSView(_ view: SourceBoundsView, context: Context) {}
}

private final class SourceBoundsView: NSView {}
