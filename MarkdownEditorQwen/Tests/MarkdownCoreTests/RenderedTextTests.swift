import XCTest
@testable import MarkdownCore

final class RenderedTextTests: XCTestCase {

    private func preview(_ source: String) -> RenderedText {
        MarkdownPipeline.rendered(from: source)
    }

    private func substring(_ text: String, _ range: Range<Int>) -> String {
        let lower = text.utf16.index(text.utf16.startIndex, offsetBy: range.lowerBound)
        let upper = text.utf16.index(lower, offsetBy: range.upperBound - range.lowerBound)
        return String(text.utf16[lower..<upper])!
    }

    func testHeadingMarkerStripped() {
        let result = preview("# Hello")
        XCTAssertEqual(result.text, "Hello")
        let heading = result.ops.filter { if case .heading = $0.token { return true }; return false }
        XCTAssertEqual(heading.count, 1)
        XCTAssertEqual(substring(result.text, heading[0].range), "Hello")
    }

    func testStrongStrippedAroundChinese() {
        let result = preview("**粗体**中文😀")
        XCTAssertEqual(result.text, "粗体中文😀")
        let strong = result.ops.filter { $0.token == .strong }
        XCTAssertEqual(strong.count, 1)
        XCTAssertEqual(substring(result.text, strong[0].range), "粗体")
    }

    func testLinkCollapsedToText() {
        let result = preview("see [docs](https://example.com) here")
        XCTAssertEqual(result.text, "see docs here")
        let link = result.ops.filter { if case .link = $0.token { return true }; return false }
        XCTAssertEqual(substring(result.text, link[0].range), "docs")
    }

    func testInlineCodeBackticksStripped() {
        let result = preview("run `swift test` now")
        XCTAssertEqual(result.text, "run swift test now")
        let code = result.ops.filter { $0.token == .inlineCode }
        XCTAssertEqual(substring(result.text, code[0].range), "swift test")
    }

    func testCodeBlockFencesStripped() {
        let result = preview("```swift\nlet a = 1\n```")
        XCTAssertEqual(result.text, "let a = 1\n")
        let block = result.ops.filter { if case .codeBlock = $0.token { return true }; return false }
        XCTAssertEqual(block.count, 1)
        XCTAssertEqual(substring(result.text, block[0].range), "let a = 1\n")
    }

    func testQuoteMarkerStripped() {
        let result = preview("> quoted\n> more")
        XCTAssertEqual(result.text, "quoted\nmore")
        let quote = result.ops.filter { if case .quote = $0.token { return true }; return false }
        XCTAssertEqual(quote.count, 1)
        XCTAssertEqual(substring(result.text, quote[0].range), "quoted\nmore")
    }

    func testListItemMarkersKeptAsBullets() {
        let result = preview("- first\n- second")
        XCTAssertEqual(result.text, "- first\n- second")
        let items = result.ops.filter { if case .listItem = $0.token { return true }; return false }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(substring(result.text, items[0].range), "- first")
        XCTAssertEqual(substring(result.text, items[1].range), "- second")
    }

    func testOnlyListMarkersRemain() {
        let result = preview("# T\n\n**a** *b* `c` [d](e)\n\n> q\n- i")
        for op in result.ops {
            if case .marker(let kind) = op.token {
                XCTAssertEqual(kind, .list, "unexpected surviving marker: \(op)")
            }
        }
    }

    func testRemappedRangesStayInBounds() {
        let source = "# 标题😀\n**strong** 中文\n- item `code`"
        let result = preview(source)
        for op in result.ops {
            XCTAssertGreaterThanOrEqual(op.range.lowerBound, 0)
            XCTAssertLessThanOrEqual(op.range.upperBound, result.text.utf16.count,
                                     "op \(op.token) out of bounds")
        }
    }
}
