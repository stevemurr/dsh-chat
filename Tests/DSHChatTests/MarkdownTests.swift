import XCTest
@testable import DSHChat

final class MarkdownTests: XCTestCase {
    func testRendersStructuredAnswerWithLinksAndList() {
        let markdown = "# An answer\n\nRead [the source](https://example.com).\n\n- First point\n- Second point\n\n1. Next step"
        XCTAssertEqual(ChatMarkdown.blocks(markdown), [
            .heading(1, "An answer"), .paragraph("Read [the source](https://example.com)."),
            .listItem("•", "First point"), .listItem("•", "Second point"), .listItem("1.", "Next step")
        ])
        let linked = ChatMarkdown.inline("Read [the source](https://example.com).")
        XCTAssertTrue(linked.runs.contains { $0.link?.absoluteString == "https://example.com" })
    }

    func testIncompleteStreamingFencePreservesCode() {
        XCTAssertEqual(ChatMarkdown.blocks("```swift\nlet value = 42\n"), [.code("swift", "let value = 42\n")])
    }

    func testComparisonTable() {
        XCTAssertEqual(ChatMarkdown.blocks("| Option | Benefit |\n| :--- | ---: |\n| A | Fast |\n| B | Simple |"), [
            .table(["Option", "Benefit"], [["A", "Fast"], ["B", "Simple"]])
        ])
    }

    func testNonTablePipesRemainText() {
        XCTAssertEqual(ChatMarkdown.blocks("A | B\nthese are choices"), [.paragraph("A | B\nthese are choices")])
    }
}
