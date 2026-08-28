import UIKit
import MarkdownCore
import MPITextKit

/// Materializes `RenderedText` into an `NSAttributedString` styled for the preview,
/// using MPITextKit attributes (MPIBackground / MPIBlockBackground / MPILink).
///
/// Building attributed strings off the main thread is supported (MPITextKit's own
/// async examples do exactly this), which keeps typing latency off the main thread.
public enum PreviewAttributedBuilder {

    public static func attributedString(for rendered: RenderedText,
                                        theme: MarkdownTheme) -> NSAttributedString {
        let text = NSMutableAttributedString(string: rendered.text)
        let fullRange = NSRange(location: 0, length: text.length)
        let fonts = PreviewFonts(theme: theme)

        var paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = theme.bodySize * 0.25
        paragraph.paragraphSpacing = theme.paragraphSpacing
        text.addAttributes([
            .font: fonts.body,
            .foregroundColor: UIColor(theme.textColor),
            .paragraphStyle: paragraph,
        ], range: fullRange)

        for op in rendered.ops {
            let range = NSRange(location: op.range.lowerBound, length: op.range.count)
            guard range.location >= 0, NSMaxRange(range) <= text.length else { continue }
            apply(op.token, range: range, theme: theme, fonts: fonts, in: text)
        }
        return text
    }

    private static func apply(_ token: StyleToken, range: NSRange,
                              theme: MarkdownTheme, fonts: PreviewFonts,
                              in text: NSMutableAttributedString) {
        switch token {
        case .heading(let level):
            let size = theme.bodySize * theme.headingScale(for: level)
            text.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: size), range: range)
            text.addAttribute(.foregroundColor, value: UIColor(theme.headingColor), range: range)
            mutateParagraphStyle(in: text, range: range) { style in
                style.paragraphSpacingBefore = theme.paragraphSpacing * 1.2
                style.paragraphSpacing = theme.paragraphSpacing * 0.6
                style.minimumLineHeight = size * 1.22
            }

        case .strong:
            enumerateFont(in: text, range: range) { font in font.withWeight(.bold) }
            text.addAttribute(.foregroundColor, value: UIColor(theme.strongColor), range: range)

        case .emphasis:
            enumerateFont(in: text, range: range) { font in font.withItalicTrait() }
            text.addAttribute(.foregroundColor, value: UIColor(theme.emphasisColor), range: range)

        case .strikethrough:
            text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            text.addAttribute(.foregroundColor, value: UIColor(theme.strikethroughColor), range: range)

        case .inlineCode:
            text.addAttribute(.font, value: fonts.code, range: range)
            text.addAttribute(.foregroundColor, value: UIColor(theme.codeColor), range: range)
            let background = MPITextBackground(fill: UIColor(theme.codeBackgroundColor),
                                               cornerRadius: 4)
            background.insets = UIEdgeInsets(top: -2, left: -1, bottom: -2, right: -1)
            text.addAttribute(.MPIBackground, value: background, range: range)

        case .codeBlock:
            text.addAttribute(.font, value: fonts.code, range: range)
            text.addAttribute(.foregroundColor, value: UIColor(theme.codeColor), range: range)
            let background = MPICodeBlockBackground(fill: UIColor(theme.codeBlockBackground),
                                                    cornerRadius: 8)
            background.insets = UIEdgeInsets(top: -6, left: -8, bottom: -6, right: -8)
            text.addAttribute(.MPIBlockBackground, value: background, range: range)
            mutateParagraphStyle(in: text, range: range) { style in
                style.paragraphSpacing = 2
                style.lineSpacing = 3
            }

        case .link(let destination):
            text.addAttribute(.foregroundColor, value: UIColor(theme.linkColor), range: range)
            text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            if let destination {
                let link = MPITextLink(value: destination as NSURL)
                text.addAttribute(.MPILink, value: link, range: range)
            }

        case .image:
            text.addAttribute(.foregroundColor, value: UIColor(theme.linkColor), range: range)

        case .quote(let depth):
            text.addAttribute(.foregroundColor, value: UIColor(theme.quoteColor), range: range)
            let bar = MPIQuoteBarBackground(barColor: UIColor(theme.quoteBarColor))
            text.addAttribute(.MPIBlockBackground, value: bar, range: range)
            mutateParagraphStyle(in: text, range: range) { style in
                let indent = theme.indentPerDepth * CGFloat(depth)
                style.headIndent = indent
                style.firstLineHeadIndent = indent
            }

        case .listItem(let depth):
            mutateParagraphStyle(in: text, range: range) { style in
                let indent = theme.indentPerDepth * CGFloat(depth)
                style.headIndent = indent
                style.firstLineHeadIndent = 0
            }

        case .marker(let kind):
            switch kind {
            case .list:
                text.addAttribute(.foregroundColor, value: UIColor(theme.linkColor), range: range)
                enumerateFont(in: text, range: range) { $0.withWeight(.semibold) }
            default:
                text.addAttribute(.foregroundColor, value: UIColor(theme.markerColor), range: range)
            }

        case .thematicBreak:
            text.addAttribute(.foregroundColor, value: UIColor(theme.thematicBreakColor), range: range)

        case .table:
            text.addAttribute(.font, value: fonts.code, range: range)

        case .html:
            text.addAttribute(.foregroundColor, value: UIColor(theme.markerColor), range: range)
        }
    }

    private static func enumerateFont(in text: NSMutableAttributedString, range: NSRange,
                                      _ transform: (UIFont) -> UIFont) {
        text.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let base = value as? UIFont ?? UIFont.systemFont(ofSize: 16)
            text.addAttribute(.font, value: transform(base), range: subrange)
        }
    }

    private static func mutateParagraphStyle(in text: NSMutableAttributedString, range: NSRange,
                                             _ mutate: (NSMutableParagraphStyle) -> Void) {
        text.enumerateAttribute(.paragraphStyle, in: range) { value, subrange, _ in
            let style: NSMutableParagraphStyle
            if let existing = value as? NSParagraphStyle {
                style = existing.mutableCopy() as! NSMutableParagraphStyle
            } else {
                style = NSMutableParagraphStyle()
            }
            mutate(style)
            text.addAttribute(.paragraphStyle, value: style, range: subrange)
        }
    }
}

struct PreviewFonts {
    let body: UIFont
    let code: UIFont

    init(theme: MarkdownTheme) {
        body = UIFont.systemFont(ofSize: theme.bodySize)
        let name = theme.codeFontName ?? "Menlo"
        code = UIFont(name: name, size: theme.bodySize - 1)
            ?? UIFont.monospacedSystemFont(ofSize: theme.bodySize - 1, weight: .regular)
    }
}

private extension UIColor {
    convenience init(_ color: MDColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

private extension UIFont {
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
