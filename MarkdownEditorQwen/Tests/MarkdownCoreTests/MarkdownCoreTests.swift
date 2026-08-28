import XCTest
import Markdown
@testable import MarkdownCore

final class UTF16LineMapTests: XCTestCase {

    func testASCIIOffsets() {
        let map = UTF16LineMap(source: "abc")
        XCTAssertEqual(map.utf16Offset(line: 1, column: 1), 0)
        XCTAssertEqual(map.utf16Offset(line: 1, column: 2), 1)
        XCTAssertEqual(map.utf16Offset(line: 1, column: 4), 3)
        XCTAssertEqual(map.utf16Offset(line: 1, column: 99), 3, "columns past the line clamp")
    }

    func testChineseByteColumns() {
        // "头" is 3 UTF-8 bytes but 1 UTF-16 unit.
        let map = UTF16LineMap(source: "a头b")
        XCTAssertEqual(map.utf16Offset(line: 1, column: 1), 0) // before "a"
        XCTAssertEqual(map.utf16Offset(line: 1, column: 2), 1) // before "头"
        XCTAssertEqual(map.utf16Offset(line: 1, column: 5), 2) // before "b" (1 + 3 bytes + 1)
        XCTAssertEqual(map.utf16Offset(line: 1, column: 6), 3) // after "b"
    }

    func testEmojiSurrogatePairs() {
        // "😀" is 4 UTF-8 bytes but 2 UTF-16 units.
        let map = UTF16LineMap(source: "a😀b")
        XCTAssertEqual(map.utf16Offset(line: 1, column: 2), 1)
        XCTAssertEqual(map.utf16Offset(line: 1, column: 6), 3, "after emoji: 1 + 4 bytes + 1")
        let sourceRange: SourceRange = SourceLocation(line: 1, column: 1, source: nil)
            ..< SourceLocation(line: 1, column: 6, source: nil)
        XCTAssertEqual(map.utf16Range(for: sourceRange), 0..<3)
    }

    func testMultiLine() {
        let map = UTF16LineMap(source: "ab\n中c\n")
        XCTAssertEqual(map.lineCount, 3, "trailing newline starts an empty last line")
        XCTAssertEqual(map.utf16Offset(line: 2, column: 1), 3)
        XCTAssertEqual(map.utf16Offset(line: 2, column: 4), 4, "after 中 (3 bytes)")
        XCTAssertEqual(map.utf16Offset(line: 2, column: 5), 5)
        XCTAssertEqual(map.contentRange(ofLine: 2), 3..<5)
    }

    func testLineLookup() {
        let map = UTF16LineMap(source: "abc\n中文\nx")
        XCTAssertEqual(map.line(ofUTF16Offset: 0), 1)
        XCTAssertEqual(map.line(ofUTF16Offset: 2), 1)
        XCTAssertEqual(map.line(ofUTF16Offset: 3), 1, "the newline belongs to its line")
        XCTAssertEqual(map.line(ofUTF16Offset: 4), 2)
        XCTAssertEqual(map.line(ofUTF16Offset: 6), 2)
        XCTAssertEqual(map.line(ofUTF16Offset: 7), 3)
        XCTAssertEqual(map.line(ofUTF16Offset: 999), 3)
    }

    func testEmptySource() {
        let map = UTF16LineMap(source: "")
        XCTAssertEqual(map.lineCount, 1)
        XCTAssertEqual(map.utf16Offset(line: 1, column: 1), 0)
        XCTAssertNil(map.utf16Offset(line: 2, column: 1))
    }
}

final class MarkdownStylerTests: XCTestCase {

    private func styled(_ source: String) -> (text: String, ops: [StyleOp]) {
        let output = MarkdownPipeline.styleOps(for: source)
        return (output.text, output.ops)
    }

    private func ops(_ source: String, matching predicate: (StyleToken) -> Bool) -> [StyleOp] {
        styled(source).ops.filter { predicate($0.token) }
    }

    private func substring(_ source: String, _ range: Range<Int>) -> String {
        let text = styled(source).text
        let lower = text.utf16.index(text.utf16.startIndex, offsetBy: range.lowerBound)
        let upper = text.utf16.index(lower, offsetBy: range.upperBound - range.lowerBound)
        return String(text.utf16[lower..<upper])!
    }

    func testHeadingCoversFullLineWithMarker() {
        let heading = ops("# Hello", matching: { if case .heading(let level) = $0 { return level == 1 }; return false })
        XCTAssertEqual(heading.count, 1)
        XCTAssertEqual(heading[0].range, 0..<7)

        let marker = ops("# Hello", matching: { $0 == .marker(.heading) })
        XCTAssertEqual(marker.count, 1)
        XCTAssertEqual(substring("# Hello", marker[0].range), "# ")
    }

    func testStrongMarkersAreSplit() {
        let (_, all) = styled("**bold** rest")
        let strong = all.filter { $0.token == .strong }
        XCTAssertEqual(strong.count, 1)
        XCTAssertEqual(strong[0].range, 0..<8)

        let markers = all.filter { $0.token == .marker(.strong) }
        XCTAssertEqual(markers.count, 2)
        XCTAssertEqual(substring("**bold** rest", markers[0].range), "**")
        XCTAssertEqual(substring("**bold** rest", markers[1].range), "**")
    }

    func testStrongWithChineseAndEmoji() {
        let source = "**粗体**中文😀"
        let all = styled(source).ops
        let strong = all.filter { $0.token == .strong }
        XCTAssertEqual(strong.count, 1)
        XCTAssertEqual(substring(source, strong[0].range), "**粗体**")

        let markers = all.filter { $0.token == .marker(.strong) }
        XCTAssertEqual(markers.map { substring(source, $0.range) }, ["**", "**"])
    }

    func testEmphasisInsideStrong() {
        let source = "***both***"
        let all = styled(source).ops
        XCTAssertFalse(all.filter { $0.token == .strong }.isEmpty)
        XCTAssertFalse(all.filter { $0.token == .emphasis }.isEmpty)
    }

    func testInlineCode() {
        let source = "a `code` b"
        let all = styled(source).ops
        let code = all.filter { $0.token == .inlineCode }
        XCTAssertEqual(code.count, 1)
        XCTAssertEqual(substring(source, code[0].range), "`code`")
        let markers = all.filter { $0.token == .marker(.code) }
        XCTAssertEqual(markers.map { substring(source, $0.range) }, ["`", "`"])
    }

    func testLink() {
        let source = "[text](https://example.com)"
        let all = styled(source).ops
        let link = all.filter { if case .link = $0.token { return true }; return false }
        XCTAssertEqual(link.count, 1)
        XCTAssertEqual(substring(source, link[0].range), source)
        if case .link(let url) = link[0].token {
            XCTAssertEqual(url?.absoluteString, "https://example.com")
        }

        let markers = all.filter { $0.token == .marker(.link) }
        XCTAssertEqual(substring(source, markers[0].range), "[")
        XCTAssertEqual(substring(source, markers[1].range), "](https://example.com)")
    }

    func testCodeBlockFences() {
        let source = "```swift\nlet a = 1\n```"
        let all = styled(source).ops
        let block = all.filter { if case .codeBlock = $0.token { return true }; return false }
        XCTAssertEqual(block.count, 1)
        XCTAssertEqual(substring(source, block[0].range), source)
        if case .codeBlock(let language) = block[0].token {
            XCTAssertEqual(language, "swift")
        }
    }

    func testQuoteMarkers() {
        let source = "> quoted\n> more"
        let all = styled(source).ops
        let quote = all.filter { if case .quote = $0.token { return true }; return false }
        XCTAssertEqual(quote.count, 1)
        let markers = all.filter { $0.token == .marker(.quote) }
        XCTAssertEqual(markers.count, 2)
        for marker in markers {
            XCTAssertEqual(substring(source, marker.range), "> ")
        }
    }

    func testUnorderedListMarkers() {
        let source = "- first\n- second"
        let all = styled(source).ops
        let items = all.filter { if case .listItem = $0.token { return true }; return false }
        XCTAssertEqual(items.count, 2)
        let markers = all.filter { $0.token == .marker(.list) }
        XCTAssertEqual(markers.count, 2)
        XCTAssertEqual(substring(source, markers[0].range), "- ")
    }

    func testNormalization() {
        let (text, _) = styled("a\r\nb\tc")
        XCTAssertEqual(text, "a\nb    c")
    }

    func testRangesNeverOverlapLineBoundariesWrongly() {
        // Regression: every op range must map back to the exact source substring.
        let source = "# 标题\n\n中文段落 with **strong** and `code`.\n\n- 项目😀\n> 引文"
        let (text, all) = styled(source)
        for op in all {
            XCTAssertGreaterThanOrEqual(op.range.lowerBound, 0)
            XCTAssertLessThanOrEqual(op.range.upperBound, text.utf16.count)
            XCTAssertFalse(substring(source, op.range).isEmpty, "empty op for \(op.token)")
        }
    }

    func testDumpProducesTree() {
        let document = MarkdownPipeline.parse("# Hi")
        let dump = MarkdownPipeline.dump(document)
        XCTAssertTrue(dump.contains("Heading"), "dump: \(dump)")
    }
}
