import Foundation
import Markdown

/// A semantic style token produced from an AST node. Consumers (editor / preview)
/// map tokens to concrete font, color and background attributes.
public enum StyleToken: Sendable, Hashable {
    case heading(level: Int)
    case strong
    case emphasis
    case strikethrough
    case inlineCode
    case codeBlock(language: String?)
    case link(destination: URL?)
    case image(source: URL?)
    case quote(depth: Int)
    case listItem(depth: Int)
    case marker(MarkerKind)
    case thematicBreak
    case table
    case html

    /// Kinds of syntax markers (`#`, `**`, ``` ` ``` …) that are rendered dimmed.
    public enum MarkerKind: Sendable, Hashable {
        case heading
        case emphasis
        case strong
        case strikethrough
        case code
        case fence
        case link
        case quote
        case list
        case html
    }
}

/// A single styling operation: apply `token` to a UTF-16 range of the source text.
public struct StyleOp: Sendable, Hashable {
    public let range: Range<Int>
    public let token: StyleToken

    public init(range: Range<Int>, token: StyleToken) {
        self.range = range
        self.token = token
    }
}

/// Walks a swift-markdown AST and emits `StyleOp`s.
///
/// Ops are emitted in priority order: block-level first, inline second, markers last,
/// so consumers can apply them sequentially and let later ops win on overlap.
public struct MarkdownStyler: MarkupVisitor {
    public typealias Result = Void

    private let map: UTF16LineMap
    private var blockOps: [StyleOp] = []
    private var inlineOps: [StyleOp] = []
    private var markerOps: [StyleOp] = []
    private var quoteDepth = 0
    private var listDepth = 0

    public init(map: UTF16LineMap) {
        self.map = map
    }

    /// Run the styler over a document and return the merged, priority-ordered ops.
    public mutating func styleOps(for document: Document) -> [StyleOp] {
        visit(document)
        return blockOps + inlineOps + markerOps
    }

    // MARK: - MarkupVisitor

    public mutating func defaultVisit(_ markup: Markup) {
        for child in markup.children {
            visit(child)
        }
    }

    public mutating func visitHeading(_ heading: Heading) {
        if let range = utf16Range(of: heading) {
            blockOps.append(StyleOp(range: range, token: .heading(level: heading.level)))
            addLeadingMarker(of: heading, in: range, kind: .heading)
        }
        defaultVisit(heading)
    }

    public mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        quoteDepth += 1
        if let range = utf16Range(of: blockQuote) {
            blockOps.append(StyleOp(range: range, token: .quote(depth: quoteDepth)))
            addQuoteMarkers(in: range)
        }
        defaultVisit(blockQuote)
        quoteDepth -= 1
    }

    public mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = utf16Range(of: codeBlock) else { return }
        blockOps.append(StyleOp(range: range, token: .codeBlock(language: codeBlock.language)))
        addFenceMarkers(in: range)
        // Code blocks contain literal text; do not descend into children.
    }

    public mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        listDepth += 1
        defaultVisit(unorderedList)
        listDepth -= 1
    }

    public mutating func visitOrderedList(_ orderedList: OrderedList) {
        listDepth += 1
        defaultVisit(orderedList)
        listDepth -= 1
    }

    public mutating func visitListItem(_ listItem: ListItem) {
        if let range = utf16Range(of: listItem) {
            blockOps.append(StyleOp(range: range, token: .listItem(depth: listDepth)))
            addLeadingMarker(of: listItem, in: range, kind: .list)
        }
        defaultVisit(listItem)
    }

    public mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        if let range = utf16Range(of: thematicBreak) {
            blockOps.append(StyleOp(range: range, token: .thematicBreak))
        }
    }

    public mutating func visitHTMLBlock(_ html: HTMLBlock) {
        if let range = utf16Range(of: html) {
            blockOps.append(StyleOp(range: range, token: .html))
            markerOps.append(StyleOp(range: range, token: .marker(.html)))
        }
    }

    public mutating func visitTable(_ table: Table) {
        if let range = utf16Range(of: table) {
            blockOps.append(StyleOp(range: range, token: .table))
        }
        defaultVisit(table)
    }

    public mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let range = utf16Range(of: emphasis) {
            inlineOps.append(StyleOp(range: range, token: .emphasis))
            addSurroundingMarkers(of: emphasis, outerRange: range, kind: .emphasis)
        }
        defaultVisit(emphasis)
    }

    public mutating func visitStrong(_ strong: Strong) {
        if let range = utf16Range(of: strong) {
            inlineOps.append(StyleOp(range: range, token: .strong))
            addSurroundingMarkers(of: strong, outerRange: range, kind: .strong)
        }
        defaultVisit(strong)
    }

    public mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        if let range = utf16Range(of: strikethrough) {
            inlineOps.append(StyleOp(range: range, token: .strikethrough))
            addSurroundingMarkers(of: strikethrough, outerRange: range, kind: .strikethrough)
        }
        defaultVisit(strikethrough)
    }

    public mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let range = utf16Range(of: inlineCode) else { return }
        inlineOps.append(StyleOp(range: range, token: .inlineCode))
        addBacktickMarkers(in: range)
    }

    public mutating func visitLink(_ link: Link) {
        if let range = utf16Range(of: link) {
            let destination = link.destination.flatMap { URL(string: $0) }
            inlineOps.append(StyleOp(range: range, token: .link(destination: destination)))
            addSurroundingMarkers(of: link, outerRange: range, kind: .link)
        }
        defaultVisit(link)
    }

    public mutating func visitImage(_ image: Image) {
        if let range = utf16Range(of: image) {
            let source = image.source.flatMap { URL(string: $0) }
            inlineOps.append(StyleOp(range: range, token: .image(source: source)))
            addSurroundingMarkers(of: image, outerRange: range, kind: .link)
        }
        defaultVisit(image)
    }

    public mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        if let range = utf16Range(of: inlineHTML) {
            inlineOps.append(StyleOp(range: range, token: .html))
            markerOps.append(StyleOp(range: range, token: .marker(.html)))
        }
    }

    // MARK: - Helpers

    private func utf16Range(of markup: Markup) -> Range<Int>? {
        guard let sourceRange = markup.range else { return nil }
        return map.utf16Range(for: sourceRange)
    }

    /// Marker between the start of `markup` and the start of its first child
    /// (e.g. the `#` of a heading, the `- ` of a list item).
    private mutating func addLeadingMarker(of markup: Markup, in outerRange: Range<Int>, kind: StyleToken.MarkerKind) {
        guard let firstChild = markup.children.first(where: { utf16Range(of: $0) != nil }),
              let firstRange = utf16Range(of: firstChild),
              outerRange.lowerBound < firstRange.lowerBound
        else { return }
        markerOps.append(StyleOp(range: outerRange.lowerBound..<firstRange.lowerBound,
                                 token: .marker(kind)))
    }

    /// Markers wrapping an inline node's content (e.g. `**`, `` ` ``, `[ ](…)`).
    private mutating func addSurroundingMarkers(of markup: Markup, outerRange: Range<Int>, kind: StyleToken.MarkerKind) {
        let children = markup.children.compactMap { child -> Range<Int>? in
            utf16Range(of: child)
        }
        if children.isEmpty {
            // No positioned children: the whole node is syntax (e.g. empty inline code).
            markerOps.append(StyleOp(range: outerRange, token: .marker(kind)))
            return
        }
        let contentStart = children.map(\.lowerBound).min() ?? outerRange.upperBound
        let contentEnd = children.map(\.upperBound).max() ?? outerRange.lowerBound
        if outerRange.lowerBound < contentStart {
            markerOps.append(StyleOp(range: outerRange.lowerBound..<contentStart,
                                     token: .marker(kind)))
        }
        if contentEnd < outerRange.upperBound {
            markerOps.append(StyleOp(range: contentEnd..<outerRange.upperBound,
                                     token: .marker(kind)))
        }
    }

    /// `>` markers at the beginning of every line covered by `range`.
    private mutating func addQuoteMarkers(in range: Range<Int>) {
        guard range.upperBound > range.lowerBound else { return }
        let firstLine = map.line(ofUTF16Offset: range.lowerBound)
        let lastLine = map.line(ofUTF16Offset: range.upperBound - 1)
        guard firstLine <= lastLine else { return }
        for lineNumber in firstLine...lastLine {
            guard let content = map.lineContent(ofLine: lineNumber),
                  let lineStart = map.contentRange(ofLine: lineNumber)?.lowerBound
            else { continue }
            var index = content.startIndex
            var utf16Units = 0
            while index < content.endIndex, content[index].isWhitespace {
                utf16Units += content[index].utf16.count
                index = content.index(after: index)
            }
            guard index < content.endIndex, content[index] == ">" else { continue }
            utf16Units += 1
            let afterArrow = content.index(after: index)
            if afterArrow < content.endIndex, content[afterArrow] == " " {
                utf16Units += 1
            }
            let markerRange = lineStart..<lineStart + utf16Units
            guard range.contains(markerRange.lowerBound) else { continue }
            markerOps.append(StyleOp(range: markerRange, token: .marker(.quote)))
        }
    }

    /// Leading/trailing backtick runs of an inline code span. The opening and closing
    /// runs always have equal length per CommonMark, so counting one gives both.
    private mutating func addBacktickMarkers(in range: Range<Int>) {
        let utf16 = Array(map.source.utf16)
        let backtick = UInt16(UnicodeScalar("`").value)
        var leading = 0
        var index = range.lowerBound
        while index < range.upperBound, utf16[index] == backtick {
            leading += 1
            index += 1
        }
        guard leading > 0, leading * 2 <= range.count else { return }
        markerOps.append(StyleOp(range: range.lowerBound..<range.lowerBound + leading,
                                 token: .marker(.code)))
        markerOps.append(StyleOp(range: range.upperBound - leading..<range.upperBound,
                                 token: .marker(.code)))
    }

    /// Opening/closing fence lines of a fenced code block. Indented code blocks have
    /// no fences and are skipped.
    private mutating func addFenceMarkers(in range: Range<Int>) {
        let utf16 = Array(map.source.utf16)
        let newline = UInt16(UnicodeScalar("\n").value)
        let backtick = UInt16(UnicodeScalar("`").value)
        let tilde = UInt16(UnicodeScalar("~").value)
        guard range.lowerBound < range.upperBound,
              utf16[range.lowerBound] == backtick || utf16[range.lowerBound] == tilde
        else { return }

        var index = range.lowerBound
        while index < range.upperBound, utf16[index] != newline {
            index += 1
        }
        guard index < range.upperBound else { return }
        markerOps.append(StyleOp(range: range.lowerBound..<(index + 1),
                                 token: .marker(.fence)))
        let contentStart = index + 1

        var lastLineStart = contentStart
        var scan = range.upperBound - 1
        while scan >= contentStart {
            if utf16[scan] == newline {
                lastLineStart = scan + 1
                break
            }
            scan -= 1
        }
        if lastLineStart < range.upperBound,
           utf16[lastLineStart] == backtick || utf16[lastLineStart] == tilde {
            markerOps.append(StyleOp(range: lastLineStart..<range.upperBound,
                                     token: .marker(.fence)))
        }
    }
}
