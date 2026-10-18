import XCTest
@testable import DSHChat

final class SourceCompletionParityTests: XCTestCase {
    func testCompleteSourceSectionsKeepTheSamePartsWhenStreamingFinishes() {
        let fixtures = [
            "Answer.\n\n**Sources:** [First report](https://example.com/report), [Second report](https://example.org/report).",
            "Answer.\n\n## References\n\n1. [First report](https://example.com/report)\n2. [Second report](https://example.org/report)",
            "Answer.\n\n**Sources:**\n\n- [First report](https://example.com/report) — Background information.\n- [Second report](https://example.org/report) — Registration information.\n\nCheck the organizer before leaving.",
            "Answer.\n\n## Sources\n\n[Report](https://example.com/report) — Background information.\n\n## Conclusion\n\nMore information.",
            "Sources: [First report](https://example.com/report)\n\nAn observation.\n\n### Further reading\n\n- [Second report](https://example.org/report) — More context.\n\nThe end.",
            #"Sources: [Topic](https://example.com/wiki/Topic_(example)), [Escaped topic](https://example.org/path\(sample\))."#,
            #"Sources: [Article](https://example.com/report "A guide with ) details"), <https://example.org/report>."#,
            "## Comparison\n\n| Option | Detail |\n| --- | --- |\n| First | Some information. |\n\n```swift\nlet value = 1\n```\n\nSources: [Report](https://example.com/report)",
            "Sources:\n\n- [Report](https://example.com/report) — Published report [updated]."
        ]

        for markdown in fixtures {
            XCTAssertEqual(extract(markdown, streaming: true).parts,
                           extract(markdown, streaming: false).parts,
                           "The final source rendering changed for: \(markdown)")
        }
    }

    func testLinkedConcludingParagraphRemainsProseBeforeAndAfterCompletion() {
        let conclusion = "[Check the organizer](https://organizer.example.com) before leaving."
        let markdown = "Answer.\n\nSources:\n\n- [Report](https://example.com/report) — Background information.\n\n\(conclusion)"
        let final = extract(markdown, streaming: false)

        XCTAssertEqual(final.blocks, [.paragraph("Answer."), .paragraph(conclusion)])
        XCTAssertEqual(extract(markdown, streaming: true).parts, final.parts)
    }

    func testAdjacentAnnotatedParagraphsDoNotChangeRenderingAtCompletion() {
        let markdown = "Answer.\n\nSources:\n\n[First report](https://example.com/report) — First annotation.\n\n[Second report](https://example.org/report) — Second annotation."

        XCTAssertEqual(extract(markdown, streaming: true).parts,
                       extract(markdown, streaming: false).parts)
    }

    func testBalancedBracketAtEndOfAnnotationKeepsTheSameSourceDetails() {
        let markdown = "Sources:\n\n- [Report](https://example.com/report) — Published report [updated]"

        XCTAssertEqual(extract(markdown, streaming: true).parts,
                       extract(markdown, streaming: false).parts)
    }

    func testOrdinaryBulletAfterSourcesIsVisibleBeforeCompletion() {
        let markdown = "Sources:\n\n- [Report](https://example.com/report) — Background information.\n\n- Check the opening hours before leaving."
        let final = extract(markdown, streaming: false)

        XCTAssertEqual(final.blocks, [.listItem("•", "Check the opening hours before leaving.")])
        XCTAssertEqual(extract(markdown, streaming: true).parts, final.parts)
    }

    private func extract(_ markdown: String, streaming: Bool) -> MarkdownSources.Result {
        MarkdownSources.extract(from: ChatMarkdown.blocks(markdown), streaming: streaming)
    }
}
