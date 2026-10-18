import XCTest
@testable import DSHChat

final class MarkdownSourcesTests: XCTestCase {
    func testBoldFooterExtractsLinksWithoutChangingBodyLinks() {
        let body = "An answer with an [inline citation](https://example.com/context)."
        let result = extract("\(body)\n\n**Sources:** [Example report](https://example.com/report), [Another source](https://www.example.org/article).")
        XCTAssertEqual(result.blocks, [.paragraph(body)])
        XCTAssertEqual(result.sources.map(\.title), ["Example report", "Another source"])
        XCTAssertEqual(result.sources.map(\.host), ["example.com", "example.org"])
    }

    func testSourceHeadingAndNumberedList() {
        let result = extract("Answer.\n\n## References\n\n1. [First](https://example.com/one)\n2. [Second](https://example.org/two)")
        XCTAssertEqual(result.blocks, [.paragraph("Answer.")])
        XCTAssertEqual(result.sources.map(\.title), ["First", "Second"])
    }

    func testFurtherReadingParagraphAndStyledLinkTitle() {
        let result = extract("Answer.\n\n**Further reading**: [**A useful** guide](https://example.com/guide) and [More](https://example.org).")
        XCTAssertEqual(result.sources.map(\.title), ["A useful guide", "More"])
    }

    func testDeduplicatesCanonicalURLPreservingFirstTitleAndLink() {
        let result = extract("Sources: [First title](https://example.com:443#section), [Duplicate](https://example.com/), [Different page](https://example.com/other).")
        XCTAssertEqual(result.sources.map(\.title), ["First title", "Different page"])
        XCTAssertEqual(result.sources.first?.url.absoluteString, "https://example.com:443#section")
    }

    func testPreservesOrdinaryAndUnlinkedSourceProse() {
        for markdown in [
            "Read [the article](https://example.com).",
            "Some sources include [an article](https://example.com).",
            "## Sources\n\nThe full source list is unavailable."
        ] {
            XCTAssertEqual(extract(markdown), .init(blocks: ChatMarkdown.blocks(markdown), sources: []))
        }
    }

    func testAnnotatedSourceListBecomesChipsBeforeConcludingProse() {
        let conclusion = "If you are nearby, [check the organizer](https://organizer.example.com) before leaving."
        let result = extract("""
        An event is happening.

        **Sources:**

        - [Community Events List](https://events.example.com) — Annual Motor Show, Saturday · Example Museum, Sample City
        - [Motor Show](https://registration.example.com) — Registration information.
        - [Event details](https://social.example.com/event) — Show this weekend, 9am–2pm.

        \(conclusion)
        """)

        XCTAssertEqual(result.sources.map(\.title), ["Community Events List", "Motor Show", "Event details"])
        XCTAssertEqual(result.sources.first?.detail, "Community Events List — Annual Motor Show, Saturday · Example Museum, Sample City")
        XCTAssertEqual(result.sources.last?.detail, "Event details — Show this weekend, 9am–2pm.")
        XCTAssertEqual(result.parts, [
            .block(.paragraph("An event is happening.")),
            .sources(result.sources),
            .block(.paragraph(conclusion))
        ])
    }

    func testInlineSourceAnnotationRemainsAvailableInDetail() {
        let result = extract("Sources: [An article](https://example.com), which explains the distinction.")
        XCTAssertEqual(result.sources.map(\.title), ["An article"])
        XCTAssertEqual(result.sources.first?.detail, "An article, which explains the distinction.")
        XCTAssertTrue(result.blocks.isEmpty)
    }

    func testSourceHeadingWithAnnotatedParagraphPreservesFollowingHeading() {
        let result = extract("## Sources\n\n[An article](https://example.com) — a detailed explanation.\n\n## Conclusion\n\nMore information.")
        XCTAssertEqual(result.sources.map(\.title), ["An article"])
        XCTAssertEqual(result.sources.first?.detail, "An article — a detailed explanation.")
        XCTAssertEqual(result.parts, [
            .sources(result.sources),
            .block(.heading(2, "Conclusion")),
            .block(.paragraph("More information."))
        ])
    }

    func testMultipleSourceSectionsStayInTheirOriginalPositions() {
        let result = extract("Sources: [First](https://example.com)\n\nA separate observation.\n\n### Further reading\n\n- [Second](https://example.org) — more context.\n\nThe end.")
        guard result.sources.count == 2 else { return XCTFail("Expected both source sections to be converted") }
        XCTAssertEqual(result.parts, [
            .sources([result.sources[0]]),
            .block(.paragraph("A separate observation.")),
            .sources([result.sources[1]]),
            .block(.paragraph("The end."))
        ])
    }

    func testDuplicateURLRetainsAnnotations() {
        let result = extract("Sources:\n\n- [First](https://example.com)\n- [Again](https://example.com/#details) — registration details.\n- [More](https://example.com/) — opening hours.")
        XCTAssertEqual(result.sources.count, 1)
        XCTAssertEqual(result.sources.first?.title, "First")
        XCTAssertEqual(result.sources.first?.url.absoluteString, "https://example.com")
        XCTAssertEqual(result.sources.first?.detail, "Again — registration details.\nMore — opening hours.")
    }

    func testPartiallyStreamedListItemStaysVisibleAfterCompletedSource() {
        for unfinished in ["[Still arriving](https://exam", "[Still arriving"] {
            let result = extract("Sources:\n\n- [Complete](https://example.com) — published report.\n- \(unfinished)")
            XCTAssertEqual(result.sources.map(\.title), ["Complete"])
            XCTAssertEqual(result.parts, [
                .sources(result.sources),
                .block(.listItem("•", unfinished))
            ])
        }
    }

    func testBalancedLiteralBracketsInAnnotationArePreserved() {
        let result = extract("Sources:\n\n- [Complete](https://example.com) — published report [updated].")
        XCTAssertEqual(result.sources.first?.detail, "Complete — published report [updated].")
    }

    func testIncompleteStreamedSourceAndNonWebLinksRemainVisible() {
        for markdown in [
            "Sources: [An article](https://example.com), [Still arriving](https://exam",
            "Sources: [An article](https://example.com), [Still arriving",
            "Sources: [Open file](file:///tmp/example.txt)",
            "Sources: [Email](mailto:example@example.com)",
            "Sources: [Credentials](https://user:password@example.com/report)",
            "Sources: No sources available.",
            "## Sources"
        ] {
            XCTAssertEqual(extract(markdown), .init(blocks: ChatMarkdown.blocks(markdown), sources: []))
        }
    }

    func testLinkContainingParentheses() {
        let result = extract("Sources: [A topic](https://example.com/wiki/Topic_(example)).")
        XCTAssertEqual(result.sources.map(\.url.absoluteString), ["https://example.com/wiki/Topic_(example)"])
    }

    private func extract(_ markdown: String) -> MarkdownSources.Result {
        MarkdownSources.extract(from: ChatMarkdown.blocks(markdown))
    }
}
