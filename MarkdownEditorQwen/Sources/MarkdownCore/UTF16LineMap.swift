import Foundation
import Markdown

/// Maps swift-markdown source positions (1-based line + UTF-8 byte column) to UTF-16
/// offsets suitable for `NSAttributedString` / `NSRange`.
public struct UTF16LineMap: Sendable {

    private struct Line {
        let text: Substring
        let utf8Count: Int
        let utf16Count: Int
        let utf16Start: Int
    }

    private let lines: [Line]

    /// The normalized source this map was built from.
    public let source: String

    public init(source: String) {
        self.source = source
        var built: [Line] = []
        var utf16 = 0
        var lineStart = source.startIndex
        while true {
            let lineEnd = source[lineStart...].firstIndex(of: "\n") ?? source.endIndex
            let text = source[lineStart..<lineEnd]
            built.append(Line(text: text,
                              utf8Count: text.utf8.count,
                              utf16Count: text.utf16.count,
                              utf16Start: utf16))
            utf16 += text.utf16.count
            if lineEnd == source.endIndex { break }
            utf16 += 1
            lineStart = source.index(after: lineEnd)
        }
        lines = built
    }

    public var lineCount: Int { lines.count }

    /// UTF-16 offset for a 1-based line / UTF-8-byte-column position. `column == 1`
    /// means "before the first character of the line". Returns `nil` when the line
    /// does not exist; columns outside the line are clamped to the line bounds.
    public func utf16Offset(line: Int, column: Int) -> Int? {
        guard line >= 1, line <= lines.count else { return nil }
        let target = lines[line - 1]
        let byteOffset = max(0, column - 1)
        if byteOffset >= target.utf8Count {
            return target.utf16Start + target.utf16Count
        }
        var bytes = 0
        var units = 0
        for ch in target.text {
            let size = ch.utf8.count
            if bytes + size > byteOffset { break }
            bytes += size
            units += ch.utf16.count
        }
        return target.utf16Start + units
    }

    /// UTF-16 half-open range for a swift-markdown `SourceRange`.
    public func utf16Range(for sourceRange: SourceRange) -> Range<Int>? {
        guard let lower = utf16Offset(line: sourceRange.lowerBound.line,
                                      column: sourceRange.lowerBound.column),
              let upper = utf16Offset(line: sourceRange.upperBound.line,
                                      column: sourceRange.upperBound.column),
              lower < upper
        else { return nil }
        return lower..<upper
    }

    /// UTF-16 range of a line's content, excluding the newline.
    public func contentRange(ofLine line: Int) -> Range<Int>? {
        guard line >= 1, line <= lines.count else { return nil }
        let target = lines[line - 1]
        return target.utf16Start ..< target.utf16Start + target.utf16Count
    }

    /// 1-based line number containing the UTF-16 offset. An offset pointing at a
    /// newline belongs to the line before it; offsets past the end clamp to the
    /// last line.
    public func line(ofUTF16Offset offset: Int) -> Int {
        guard !lines.isEmpty else { return 1 }
        var low = 0
        var high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].utf16Start <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }

    /// The content of a line, excluding its newline.
    public func lineContent(ofLine line: Int) -> Substring? {
        guard line >= 1, line <= lines.count else { return nil }
        return lines[line - 1].text
    }
}
