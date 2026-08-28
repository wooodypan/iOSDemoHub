import Foundation
import Markdown

/// Markdown source transformed for the rendered preview: syntax markers are stripped
/// and the remaining style ops are re-mapped into the cleaned text.
public struct RenderedText: Sendable {
    /// The cleaned text shown by the preview.
    public let text: String
    /// Non-marker style ops whose ranges refer to `text`.
    public let ops: [StyleOp]
}

extension MarkdownPipeline {

    /// Build preview-ready text from markdown source: parse, style, then strip
    /// syntax markers (`#`, `**`, `` ` ``, `> `, `- `, `[ ](…)`, fences…) and re-map
    /// every remaining op range into the cleaned string.
    public static func rendered(from source: String) -> RenderedText {
        let styled = styleOps(for: source)

        var markers: [Range<Int>] = []
        var contentOps: [StyleOp] = []
        for op in styled.ops {
            // List markers stay in the preview text: they act as visible bullets.
            if case .marker(let kind) = op.token, kind != .list {
                markers.append(op.range)
            } else {
                contentOps.append(op)
            }
        }
        markers.sort { $0.lowerBound < $1.lowerBound }

        let utf16 = Array(styled.text.utf16)
        var cleaned = ""
        cleaned.reserveCapacity(utf16.count)
        var cursor = 0
        for marker in markers {
            cleaned += String(decoding: utf16[cursor..<marker.lowerBound], as: UTF16.self)
            cursor = marker.upperBound
        }
        cleaned += String(decoding: utf16[cursor...], as: UTF16.self)

        var removalBefore: [Int] = []
        removalBefore.reserveCapacity(markers.count + 1)
        var removed = 0
        for marker in markers {
            removalBefore.append(removed)
            removed += marker.count
        }
        removalBefore.append(removed)

        func remap(_ offset: Int) -> Int {
            var count = 0
            while count < markers.count, markers[count].upperBound <= offset {
                count += 1
            }
            var adjusted = offset - removalBefore[count]
            if count < markers.count, markers[count].contains(offset) {
                adjusted -= offset - markers[count].lowerBound
            }
            return adjusted
        }

        let remappedOps: [StyleOp] = contentOps.compactMap { op in
            let lower = remap(op.range.lowerBound)
            let upper = remap(op.range.upperBound)
            guard lower < upper, upper <= cleaned.utf16.count else { return nil }
            return StyleOp(range: lower..<upper, token: op.token)
        }

        return RenderedText(text: cleaned, ops: remappedOps)
    }
}
