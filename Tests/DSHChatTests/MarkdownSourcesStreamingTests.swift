import XCTest
@testable import DSHChat

final class MarkdownSourcesStreamingTests: XCTestCase {
    func testInlineSourcesNeverFlashAsTextAtAnyStreamingPrefix() {
        let first = "[A topic](https://example.com/wiki/Topic_(example))"
        let second = #"[Escaped topic](https://example.org/path\(sample\))"#
        let footer = "**Sources:** \(first), \(second)."
        let firstCompletedAt = "**Sources:** \(first)".count
        let secondCompletedAt = "**Sources:** \(first), \(second)".count
        let final = extract("Answer.\n\n\(footer)", streaming: false)
        XCTAssertEqual(final.sources.map(\.url.absoluteString), [
            "https://example.com/wiki/Topic_(example)",
            "https://example.org/path(sample)"
        ])

        // Start when a label could be recognized; isolated formatting punctuation
        // before its first letter has no source meaning yet.
        for count in 3...footer.count {
            let prefix = String(footer.prefix(count))
            let result = extract("Answer.\n\n\(prefix)")
            let expectedCount = count >= secondCompletedAt ? 2 : count >= firstCompletedAt ? 1 : 0
            XCTAssertEqual(result.blocks, [.paragraph("Answer.")], "Raw source text at prefix: \(prefix)")
            XCTAssertEqual(result.sources.map(\.id), Array(final.sources.prefix(expectedCount)).map(\.id), "Unstable or premature chips at prefix: \(prefix)")
        }
    }

    func testAnnotatedBulletSourcesNeverFlashAndCompletedChipsStayVisible() {
        let first = "[Event report](https://events.example.com/report)"
        let second = "[Registration](https://registration.example.com/show)"
        let section = "## References\n\n- \(first) — Published report with [updated] details.\n- \(second) — Opening hours."
        let firstCompletedAt = "## References\n\n- \(first)".count
        let secondCompletedAt = "## References\n\n- \(first) — Published report with [updated] details.\n- \(second)".count
        let final = extract("Answer.\n\n\(section)", streaming: false)
        XCTAssertEqual(final.sources.map(\.title), ["Event report", "Registration"])

        for count in 4...section.count {
            let prefix = String(section.prefix(count))
            let result = extract("Answer.\n\n\(prefix)")
            let expectedCount = count >= secondCompletedAt ? 2 : count >= firstCompletedAt ? 1 : 0
            XCTAssertEqual(result.blocks, [.paragraph("Answer.")], "Raw source list at prefix: \(prefix)")
            XCTAssertEqual(result.sources.map(\.id), Array(final.sources.prefix(expectedCount)).map(\.id), "A completed chip disappeared at prefix: \(prefix)")
        }
    }

    func testSourceLabelPrefixesAreHeldUntilTheyCanBecomeChips() {
        for label in ["Sources", "References", "Further reading"] {
            for style in ["\(label):", "**\(label):**", "### \(label)"] {
                let letterStart = style.firstIndex(where: \.isLetter)!
                let firstLetterCount = style.distance(from: style.startIndex, to: letterStart) + 1
                for count in firstLetterCount...style.count {
                    let prefix = String(style.prefix(count))
                    let result = extract("Answer.\n\n\(prefix)")
                    XCTAssertEqual(result.blocks, [.paragraph("Answer.")], "Source label flashed at prefix: \(prefix)")
                    XCTAssertTrue(result.sources.isEmpty)
                }
            }
        }
    }

    func testQuotedTitlesAndAutolinksWaitForTheirClosingDelimiter() {
        for link in [
            #"[Article](https://example.com/report "Guide with ) details")"#,
            #"[Article](https://example.com/report 'Guide with ) details')"#,
            "[Article](https://example.com/author's-guide)",
            "<https://example.com/report>"
        ] {
            let final = extract("Sources: " + link, streaming: false)
            XCTAssertEqual(final.sources.count, 1)
            for count in 1...link.count {
                let result = extract("Answer.\n\nSources: " + String(link.prefix(count)))
                XCTAssertEqual(result.blocks, [.paragraph("Answer.")])
                XCTAssertEqual(result.sources.map(\.id), count == link.count ? final.sources.map(\.id) : [])
            }
        }
    }

    func testConcludingProseAndOrdinaryLinksKeepStreamingAfterSourceChips() {
        let section = "Answer.\n\nSources:\n\n- [Report](https://example.com/report) — background.\n\n"
        let conclusion = "Check [the organizer](https://organizer.example.com) before leaving."
        let sourceID = extract(section).sources.first?.id
        XCTAssertNotNil(sourceID)

        for count in 1...conclusion.count {
            let tail = String(conclusion.prefix(count))
            let result = extract(section + tail)
            XCTAssertEqual(result.sources.map(\.id), [sourceID!])
            XCTAssertEqual(result.blocks, [.paragraph("Answer."), .paragraph(tail)], "Ordinary concluding prose was held: \(tail)")
        }
    }

    func testAmbiguousOrdinaryParagraphIsReleasedWhenItStopsMatchingSourceLabel() {
        let text = "Sources improve the explanation."
        for count in "Sources i".count...text.count {
            let prefix = String(text.prefix(count))
            let result = extract("Answer.\n\n\(prefix)")
            XCTAssertEqual(result.blocks, [.paragraph("Answer."), .paragraph(prefix)])
            XCTAssertTrue(result.sources.isEmpty)
        }
        for text in ["Reference material matters.", "Further reading helps explain the answer.", "Source code is useful."] {
            XCTAssertEqual(extract(text).blocks, [.paragraph(text)])
        }
    }

    func testSourceTextInsideCodeFenceIsNeverHeldOrConverted() {
        let content = "## Sources\n\n- [Example](https://example.com)"
        for count in 1...content.count {
            let markdown = "```markdown\n" + String(content.prefix(count))
            XCTAssertEqual(extract(markdown), extract(markdown, streaming: false), "Code was treated as a source section: \(markdown)")
        }
        XCTAssertEqual(extract("```markdown\n\(content)\n```").blocks, [.code("markdown", content)])
    }

    func testMalformedAndNonWebSourceTextFallsBackWhenStreamingFinishes() {
        for footer in [
            "Sources: [An article](https://example.com), [Still arriving](https://exam",
            "Sources: [Still arriving",
            "## Sources",
            "Sources: No sources available.",
            "Sources: [Email](mailto:sample@example.com)",
            "Sources: [Open file](file:///tmp/example.txt)",
            "Sources: [Credentials](https://user:password@example.com/report)"
        ] {
            let markdown = "Answer.\n\n\(footer)"
            let result = extract(markdown, streaming: false)
            XCTAssertEqual(result, MarkdownSources.extract(from: ChatMarkdown.blocks(markdown)))
            XCTAssertEqual(result.blocks, ChatMarkdown.blocks(markdown), "Final fallback lost text: \(footer)")
            XCTAssertTrue(result.sources.isEmpty)
        }
    }

    private func extract(_ markdown: String, streaming: Bool = true) -> MarkdownSources.Result {
        MarkdownSources.extract(from: ChatMarkdown.blocks(markdown), streaming: streaming)
    }
}
