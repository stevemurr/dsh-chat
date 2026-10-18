import AppKit
import DSHSession
import SwiftUI
import XCTest
@testable import DSHChat

@MainActor
final class ActivityCardPresentationTests: XCTestCase {
    /// Native, offscreen checks use only synthetic timeline items. No host
    /// connection, global shortcut, or visible app window is created.
    func testActivityCardsKeepConsistentGeometryAndWrapExpandedDetails() async throws {
        guard nativeChecksEnabled else {
            throw XCTSkip("Enable native layout checks or activity previews to inspect activity cards")
        }

        let collapsed = VStack(alignment: .leading, spacing: 12) {
            TimelineRow(item: sampleItem(.reasoning(text: Self.reasoning)), cleanUserText: { $0 })
                .background(ActivityBoundsMarker(name: "thinking"))
            TimelineRow(item: sampleItem(.tool(Self.completedSearch)), cleanUserText: { $0 })
                .background(ActivityBoundsMarker(name: "search"))
            ActivityCard(title: "Thinking", symbol: "ellipsis.bubble", status: .running, expandable: false) {
                EmptyView()
            }
            .background(ActivityBoundsMarker(name: "running"))
        }
        .frame(width: 740, alignment: .leading)
        .padding(24)
        .background(ChatTheme.background)
        let (collapsedWindow, collapsedView) = makeWindow(collapsed)
        defer { collapsedWindow.contentView = nil }
        try await settle(window: collapsedWindow, view: collapsedView)

        let frames = try ["thinking", "search", "running"].map { try markerFrame($0, in: collapsedView) }
        for frame in frames {
            XCTAssertEqual(frame.width, 740, accuracy: 0.5,
                           "Thinking, web searches, and live activity must span the conversation width")
            XCTAssertGreaterThanOrEqual(frame.height, 28, "Activity headers must retain a usable click target")
            XCTAssertTrue(collapsedView.bounds.contains(frame))
            XCTAssertEqual(frame.height, try XCTUnwrap(frames.first).height, accuracy: 0.5,
                           "Collapsed reasoning and tool cards must have matching header heights")
        }

        let expanded = ActivityCard(title: "Searched the web", symbol: "globe", status: .complete,
                                    expandable: true, initiallyExpanded: true) {
            Text(Self.longDetails)
                .font(.system(size: 14))
                .foregroundStyle(ChatTheme.secondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .background(ActivityBoundsMarker(name: "details"))
        }
        .background(ActivityBoundsMarker(name: "expanded"))
        .frame(width: 320, alignment: .leading)
        .padding(24)
        .background(ChatTheme.background)
        let (expandedWindow, expandedView) = makeWindow(expanded)
        defer { expandedWindow.contentView = nil }
        try await settle(window: expandedWindow, view: expandedView)

        let cardFrame = try markerFrame("expanded", in: expandedView)
        let detailFrame = try markerFrame("details", in: expandedView)
        XCTAssertGreaterThan(detailFrame.height, 72, "Long details must wrap across multiple readable lines")
        XCTAssertGreaterThan(cardFrame.height, frames[0].height + detailFrame.height,
                             "The expanded card must grow to contain its header and details")
        XCTAssertTrue(cardFrame.insetBy(dx: -0.5, dy: -0.5).contains(detailFrame),
                      "Expanded details must remain inside the activity card")
        XCTAssertTrue(expandedView.bounds.contains(cardFrame), "Expanded content must fit its native host")
        XCTAssertFalse(collapsedWindow.isVisible)
        XCTAssertFalse(expandedWindow.isVisible)
    }

    func testRenderNativeActivityCards() async throws {
        guard let destination = ProcessInfo.processInfo.environment["DSH_CHAT_ACTIVITY_PREVIEW_PATH"] else {
            throw XCTSkip("Set DSH_CHAT_ACTIVITY_PREVIEW_PATH to render native activity previews")
        }
        let baseURL = URL(fileURLWithPath: destination)
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            try await render(transcriptPreview, appearance: appearance, to: previewURL(baseURL, suffix: "-" + mode))
            try await render(expandedPreview, appearance: appearance, to: previewURL(baseURL, suffix: "-expanded-" + mode))
        }
    }

    private var transcriptPreview: some View {
        VStack(alignment: .leading, spacing: 28) {
            TimelineRow(item: Self.transcriptItems[0], cleanUserText: { $0 })
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(Self.transcriptItems.dropFirst().dropLast())) { item in
                    TimelineRow(item: item, cleanUserText: { $0 })
                }
            }
            if let item = Self.transcriptItems.last {
                TimelineRow(item: item, cleanUserText: { $0 })
            }
            Rectangle().fill(ChatTheme.border).frame(height: 1)
            VStack(alignment: .leading, spacing: 12) {
                ActivityCard(title: "Thinking", symbol: "ellipsis.bubble", status: .running, expandable: false) {
                    EmptyView()
                }
                TimelineRow(item: sampleItem(.tool(Self.runningSearch)), cleanUserText: { $0 })
                TimelineRow(item: sampleItem(.tool(Self.failedSearch)), cleanUserText: { $0 })
            }
        }
        .frame(width: 740, alignment: .leading)
        .padding(30)
        .background(ChatTheme.background)
    }

    private var expandedPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            ActivityCard(title: "Thinking", symbol: "ellipsis.bubble", status: .complete,
                         expandable: true, initiallyExpanded: true) {
                Text(Self.reasoning).font(.system(size: 14)).foregroundStyle(ChatTheme.secondary)
                    .lineSpacing(5).textSelection(.enabled)
            }
            ActivityCard(title: "Searched the web", symbol: "globe", status: .complete,
                         expandable: true, initiallyExpanded: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vision Quest Friday AI origin").font(.system(size: 14)).foregroundStyle(ChatTheme.secondary)
                    Text(Self.searchDetails).font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(ChatTheme.secondary).lineSpacing(4)
                }
            }
            ActivityCard(title: "Searching the web", symbol: "globe", status: .running, expandable: false) {
                EmptyView()
            }
            ActivityCard(title: "Search failed", symbol: "globe", status: .failed,
                         expandable: true, initiallyExpanded: true) {
                Text("The page could not be reached. Try the search again.")
                    .font(.system(size: 14)).foregroundStyle(ChatTheme.warning).lineSpacing(5)
            }
        }
        .frame(width: 740, alignment: .leading)
        .padding(30)
        .background(ChatTheme.background)
    }

    private var nativeChecksEnabled: Bool {
        ProcessInfo.processInfo.environment["DSH_CHAT_NATIVE_LAYOUT_CHECK"] == "1"
            || ProcessInfo.processInfo.environment["DSH_CHAT_ACTIVITY_PREVIEW_PATH"] != nil
    }

    private func sampleItem(_ content: TimelineContent) -> TimelineItem {
        TimelineItem(id: "sample", seq: 1, time: .distantPast, content: content, turn: 1)
    }

    private func makeWindow<Content: View>(_ content: Content) -> (NSPanel, NSHostingView<Content>) {
        let view = NSHostingView(rootView: content)
        let size = NSSize(width: ceil(view.fittingSize.width), height: ceil(view.fittingSize.height))
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

    private func render<Content: View>(_ content: Content, appearance: NSAppearance.Name,
                                      to destination: URL) async throws {
        let (window, view) = makeWindow(content)
        defer { window.contentView = nil }
        window.appearance = try XCTUnwrap(NSAppearance(named: appearance))
        try await settle(window: window, view: view)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: destination)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(view.bounds.width, 800, accuracy: 0.5)
    }

    private func markerFrame(_ name: String, in view: NSView) throws -> NSRect {
        let marker = try XCTUnwrap(descendants(of: view).compactMap { $0 as? ActivityBoundsView }
            .first { $0.markerName == name })
        return marker.convert(marker.bounds, to: view)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func previewURL(_ baseURL: URL, suffix: String) -> URL {
        baseURL.deletingLastPathComponent()
            .appendingPathComponent(baseURL.deletingPathExtension().lastPathComponent + suffix)
            .appendingPathExtension(baseURL.pathExtension)
    }

    private static let reasoning = "I’ll check recent sources to understand where Friday comes from and how the character connects to the story."
    private static let searchDetails = "Found 3 relevant pages.\n• Character background and appearances\n• Vision Quest series coverage\n• Connections to Tony Stark’s AI assistants"
    private static let longDetails = "Query: Vision Quest Friday AI origin. The results include character background, coverage of the series, and connections to Tony Stark’s earlier AI assistants. Each result has a title and source description, so the answer can explain the connection in context. This longer detail also checks that a narrow activity card keeps its complete text visible without clipping at the bottom or extending past the right edge."

    private static let completedSearch = ToolCallItem(callId: "search-complete", name: "web_search",
                                                      arguments: #"{"query":"Vision Quest Friday AI origin"}"#,
                                                      result: ToolResult(text: searchDetails, isError: false))
    private static let runningSearch = ToolCallItem(callId: "search-running", name: "web_search",
                                                    arguments: #"{"query":"Vision Quest latest news"}"#)
    private static let failedSearch = ToolCallItem(callId: "search-failed", name: "web_search",
                                                   arguments: #"{"query":"Friday AI origin"}"#,
                                                   result: ToolResult(text: "The page could not be reached. Try the search again.", isError: true))
    private static var transcriptItems: [TimelineItem] {
        let contents: [TimelineContent] = [
            .user(text: "Where does Friday come from in the Vision Quest series?", imageCount: 0),
            .reasoning(text: reasoning),
            .tool(completedSearch),
            .reasoning(text: "I have enough context to connect the character’s background with the series."),
            .assistant(markdown: "Friday is one of **Tony Stark’s AI assistants** in the Marvel Cinematic Universe. The series explores the connections between these AI characters and Vision."),
        ]
        return contents.enumerated().map { index, content in
            TimelineItem(id: "preview-\(index)", seq: index, time: .distantPast, content: content, turn: 1)
        }
    }
}

private struct ActivityBoundsMarker: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> ActivityBoundsView { ActivityBoundsView(name: name) }
    func updateNSView(_ view: ActivityBoundsView, context: Context) { view.markerName = name }
}

private final class ActivityBoundsView: NSView {
    var markerName: String
    init(name: String) {
        markerName = name
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
}
