import AppKit
import SwiftUI
import XCTest
@testable import DSHChat

@MainActor
final class MarkdownTablePresentationTests: XCTestCase {
    /// Exercise the rendered Markdown rather than its width calculation: a
    /// narrow answer must grow vertically to retain every table cell.
    func testOrdinaryTablesWrapToTheAvailableAnswerWidth() async throws {
        guard nativeChecksEnabled else {
            throw XCTSkip("Enable native layout checks or table previews to check table wrapping")
        }

        for markdown in [Self.twoColumnTable, Self.threeColumnTable] {
            var heights: [CGFloat] = []
            for width in [CGFloat(400), 720, 1280] {
                let (window, view) = makeWindow(markdown: markdown, width: width)
                defer { window.contentView = nil }
                try await settle(window: window, view: view)

                XCTAssertEqual(view.bounds.width, width + 40, accuracy: 0.5)
                XCTAssertGreaterThan(view.bounds.height, 100, "The complete table must contribute to the answer's height")
                heights.append(view.bounds.height)
                for scroll in descendants(of: view).compactMap({ $0 as? NSScrollView }) {
                    guard scroll.hasHorizontalScroller, let document = scroll.documentView else { continue }
                    XCTAssertLessThanOrEqual(document.bounds.width, scroll.contentView.bounds.width + 1,
                                             "Ordinary two- and three-column tables must fit without horizontal overflow")
                }
                XCTAssertFalse(window.isVisible)
            }
            XCTAssertGreaterThan(heights[0], heights[1] + 30,
                                 "At a narrow answer width, long cells must wrap into additional visible lines")
            XCTAssertGreaterThan(heights[1], heights[2] + 15,
                                 "Table rows must become more compact as the available answer width increases")
        }
    }

    func testManyColumnsRemainReachableWithOverlayScrolling() async throws {
        guard nativeChecksEnabled else {
            throw XCTSkip("Enable native layout checks or table previews to check wide tables")
        }
        let (window, view) = makeWindow(markdown: Self.manyColumnTable, width: 400)
        defer { window.contentView = nil }
        try await settle(window: window, view: view)

        let scroll = try XCTUnwrap(descendants(of: view).compactMap { $0 as? NSScrollView }
            .first { $0.hasHorizontalScroller })
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.bounds.width, scroll.contentView.bounds.width + 100,
                             "A table with many columns must retain all columns in a scrollable document")
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
        XCTAssertTrue(scroll.autohidesScrollers)
        XCTAssertLessThanOrEqual(scroll.bounds.width, 400.5, "The scroll viewport must stay within the answer")
        XCTAssertFalse(window.isVisible)
    }

    func testRenderNativeTableWidthsAndAppearances() async throws {
        guard let path = ProcessInfo.processInfo.environment["DSH_CHAT_TABLE_PREVIEW_PATH"] else {
            throw XCTSkip("Set DSH_CHAT_TABLE_PREVIEW_PATH to render native table previews")
        }
        let destination = URL(fileURLWithPath: path)
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for width in [CGFloat(400), 720, 1280] {
                let markdown = "## A readable comparison\n\n" + Self.twoColumnTable
                    + "\n\n### Sources and details\n\n" + Self.threeColumnTable
                let (window, view) = makeWindow(markdown: markdown, width: width)
                defer { window.contentView = nil }
                window.appearance = try XCTUnwrap(NSAppearance(named: appearance))
                try await settle(window: window, view: view)
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let url = destination.deletingLastPathComponent()
                    .appendingPathComponent(destination.deletingPathExtension().lastPathComponent + "-\(Int(width))-\(mode)")
                    .appendingPathExtension(destination.pathExtension)
                try png.write(to: url)
                XCTAssertFalse(window.isVisible)
            }
        }
    }

    private var nativeChecksEnabled: Bool {
        ProcessInfo.processInfo.environment["DSH_CHAT_NATIVE_LAYOUT_CHECK"] == "1"
            || ProcessInfo.processInfo.environment["DSH_CHAT_TABLE_PREVIEW_PATH"] != nil
    }

    private func makeWindow(markdown: String, width: CGFloat) -> (NSPanel, NSView) {
        let view = NSHostingView(rootView: MarkdownContent(text: markdown)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
            .background(ChatTheme.background))
        let size = NSSize(width: width + 40, height: ceil(view.fittingSize.height))
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

    private static let twoColumnTable = """
    | Scheme | How it works |
    | --- | --- |
    | OpenPGP / GPG | Public-key encryption and symmetric session keys; typically exchanged through an email client with a compatible extension. Long explanations must remain fully readable within this cell. |
    | S/MIME | Certificate-based encryption, with certificates issued by an organization or certificate authority and configured for each account. |
    | Hosted mail | Server-integrated key generation and recovery, with a guided setup flow and a clear explanation of the account's recovery options. |
    | Transport encryption | HTTPS between clients and servers. **This description includes bold text** and *an italic phrase* so inline styling must continue to wrap normally. |
    """

    private static let threeColumnTable = """
    | Source | Detail | Reference |
    | --- | --- | --- |
    | Product documentation | An explanation of account setup, recovery, and compatibility with other clients, including the complete details rather than a clipped line. | https://example.com/documentation/email-encryption/compatibility-and-recovery-options-for-different-clients |
    | Release notes | A longer description of the changes and the steps needed to adopt them safely across a group of accounts. | [Read the full release notes](https://example.com/release-notes) |
    | Support guide | A practical checklist for diagnosing setup problems and choosing the appropriate account settings. | https://example.com/help/abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789 |
    """

    private static let manyColumnTable = """
    | Name | Owner | Status | Created | Updated | Description | Reference |
    | --- | --- | --- | --- | --- | --- | --- |
    | Example | Team | Available | Monday | Tuesday | A wide table keeps all of its columns reachable. | Documentation |
    | Another example | Support | Pending | Wednesday | Thursday | Each cell retains a usable reading width. | Guide |
    """
}
