import UIKit
import MarkdownCore

/// Materializes `StyleToken`s into concrete `NSAttributedString` attributes for the
/// editor's text storage. Fonts are derived from whatever attributes already exist at
/// the target range so that overlapping tokens compose (e.g. strong inside a heading
/// stays bold *and* keeps the heading size).
@MainActor
struct TokenAttributes {

    let theme: MarkdownTheme

    var bodyFont: UIFont {
        UIFont.systemFont(ofSize: theme.bodySize)
    }

    var codeFont: UIFont {
        let name = theme.codeFontName ?? "Menlo"
        return UIFont(name: name, size: theme.bodySize - 1)
            ?? UIFont.monospacedSystemFont(ofSize: theme.bodySize - 1, weight: .regular)
    }

    /// Attributes applied to the whole document before per-token styling.
    var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = theme.bodySize * 0.22
        paragraph.paragraphSpacing = theme.paragraphSpacing * 0.5
        return [
            .font: bodyFont,
            .foregroundColor: UIColor(theme.textColor),
            .paragraphStyle: paragraph,
        ]
    }

    func apply(_ token: StyleToken, range: NSRange, in storage: NSTextStorage) {
        switch token {
        case .heading(let level):
            let size = theme.bodySize * theme.headingScale(for: level)
            replaceFont(in: storage, range: range) { _ in
                UIFont.boldSystemFont(ofSize: size)
            }
            storage.addAttribute(.foregroundColor, value: UIColor(theme.headingColor), range: range)
            applyParagraphStyle(in: storage, range: range) { style in
                style.paragraphSpacingBefore = theme.paragraphSpacing
                style.paragraphSpacing = theme.paragraphSpacing * 0.6
                style.minimumLineHeight = size * 1.25
            }

        case .strong:
            deriveFont(in: storage, range: range) { font in
                font.withWeight(.bold)
            }
            storage.addAttribute(.foregroundColor, value: UIColor(theme.strongColor), range: range)

        case .emphasis:
            deriveFont(in: storage, range: range) { font in
                font.withItalicTrait()
            }
            storage.addAttribute(.foregroundColor, value: UIColor(theme.emphasisColor), range: range)

        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            storage.addAttribute(.foregroundColor, value: UIColor(theme.strikethroughColor), range: range)

        case .inlineCode:
            replaceFont(in: storage, range: range) { _ in codeFont }
            storage.addAttribute(.foregroundColor, value: UIColor(theme.codeColor), range: range)
            storage.addAttribute(.backgroundColor, value: UIColor(theme.codeBackgroundColor), range: range)

        case .codeBlock:
            replaceFont(in: storage, range: range) { _ in codeFont }
            storage.addAttribute(.foregroundColor, value: UIColor(theme.codeColor), range: range)
            storage.addAttribute(.backgroundColor, value: UIColor(theme.codeBlockBackground), range: range)
            applyParagraphStyle(in: storage, range: range) { style in
                style.paragraphSpacing = 0
                style.lineSpacing = 2
            }

        case .link(let destination):
            storage.addAttribute(.foregroundColor, value: UIColor(theme.linkColor), range: range)
            if destination != nil {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }

        case .image:
            storage.addAttribute(.foregroundColor, value: UIColor(theme.linkColor), range: range)

        case .quote(let depth):
            storage.addAttribute(.foregroundColor, value: UIColor(theme.quoteColor), range: range)
            applyParagraphStyle(in: storage, range: range) { style in
                let indent = theme.indentPerDepth * CGFloat(depth)
                style.headIndent = indent
                style.firstLineHeadIndent = indent * 0.25
                style.tailIndent = 0
            }

        case .listItem(let depth):
            applyParagraphStyle(in: storage, range: range) { style in
                let indent = theme.indentPerDepth * CGFloat(depth)
                style.headIndent = indent
                style.firstLineHeadIndent = max(0, indent - theme.indentPerDepth * 0.75)
            }

        case .marker:
            storage.addAttribute(.foregroundColor, value: UIColor(theme.markerColor), range: range)

        case .thematicBreak:
            storage.addAttribute(.foregroundColor, value: UIColor(theme.thematicBreakColor), range: range)

        case .table:
            replaceFont(in: storage, range: range) { _ in codeFont }

        case .html:
            storage.addAttribute(.foregroundColor, value: UIColor(theme.markerColor), range: range)
        }
    }

    // MARK: - Font composition

    /// Replace the font over the range, computing the replacement from the existing one.
    private func replaceFont(in storage: NSTextStorage, range: NSRange,
                             _ transform: (UIFont) -> UIFont) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let base = value as? UIFont ?? bodyFont
            storage.addAttribute(.font, value: transform(base), range: subrange)
        }
    }

    /// Derive a new font from the existing one so overlapping styles compose.
    private func deriveFont(in storage: NSTextStorage, range: NSRange,
                            _ transform: (UIFont) -> UIFont) {
        replaceFont(in: storage, range: range, transform)
    }

    /// Apply paragraph style changes per-paragraph; NSTextStorage splits the range at
    /// paragraph boundaries automatically when a paragraph style is set.
    private func applyParagraphStyle(in storage: NSTextStorage, range: NSRange,
                                     _ mutate: (NSMutableParagraphStyle) -> Void) {
        storage.enumerateAttribute(.paragraphStyle, in: range) { value, subrange, _ in
            let style: NSMutableParagraphStyle
            if let existing = value as? NSParagraphStyle {
                style = existing.mutableCopy() as! NSMutableParagraphStyle
            } else {
                style = NSMutableParagraphStyle()
                style.lineSpacing = theme.bodySize * 0.22
            }
            mutate(style)
            storage.addAttribute(.paragraphStyle, value: style, range: subrange)
        }
    }
}

private extension UIColor {
    convenience init(_ color: MDColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: pointSize)
    }

    func withItalicTrait() -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(
            fontDescriptor.symbolicTraits.union(.traitItalic)
        ) ?? fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
