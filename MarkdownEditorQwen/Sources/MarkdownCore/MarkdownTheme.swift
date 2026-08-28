import Foundation

/// A platform-agnostic RGBA color so `MarkdownCore` stays UIKit-free.
public struct MDColor: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(gray: Double, alpha: Double = 1) {
        self.init(red: gray, green: gray, blue: gray, alpha: alpha)
    }
}

/// Semantic styling values shared by the editor and the preview.
public struct MarkdownTheme: Sendable {

    // MARK: Typography

    /// Body font size in points.
    public var bodySize: Double
    /// Font-size multiplier for each heading level (index 0 = h1 … index 5 = h6).
    public var headingScales: [Double]
    /// Monospaced font name for code; falls back to the system mono font when nil.
    public var codeFontName: String?
    /// Weight used for strong text.
    public var strongWeight: Double
    /// Extra space after block elements, in points.
    public var paragraphSpacing: Double
    /// Head indent per quote/list depth, in points.
    public var indentPerDepth: Double

    // MARK: Colors

    public var textColor: MDColor
    /// Dimmed color for syntax markers (`#`, `**`, …).
    public var markerColor: MDColor
    public var headingColor: MDColor
    public var strongColor: MDColor
    public var emphasisColor: MDColor
    public var strikethroughColor: MDColor
    public var codeColor: MDColor
    public var codeBackgroundColor: MDColor
    public var codeBlockBackground: MDColor
    public var linkColor: MDColor
    public var quoteColor: MDColor
    public var quoteBarColor: MDColor
    public var tableBorderColor: MDColor
    public var thematicBreakColor: MDColor

    public init(
        bodySize: Double = 16,
        headingScales: [Double] = [1.55, 1.35, 1.2, 1.1, 1.0, 0.92],
        codeFontName: String? = nil,
        strongWeight: Double = 0.62,
        paragraphSpacing: Double = 8,
        indentPerDepth: Double = 16,
        textColor: MDColor,
        markerColor: MDColor,
        headingColor: MDColor,
        strongColor: MDColor,
        emphasisColor: MDColor,
        strikethroughColor: MDColor,
        codeColor: MDColor,
        codeBackgroundColor: MDColor,
        codeBlockBackground: MDColor,
        linkColor: MDColor,
        quoteColor: MDColor,
        quoteBarColor: MDColor,
        tableBorderColor: MDColor,
        thematicBreakColor: MDColor
    ) {
        self.bodySize = bodySize
        self.headingScales = headingScales
        self.codeFontName = codeFontName
        self.strongWeight = strongWeight
        self.paragraphSpacing = paragraphSpacing
        self.indentPerDepth = indentPerDepth
        self.textColor = textColor
        self.markerColor = markerColor
        self.headingColor = headingColor
        self.strongColor = strongColor
        self.emphasisColor = emphasisColor
        self.strikethroughColor = strikethroughColor
        self.codeColor = codeColor
        self.codeBackgroundColor = codeBackgroundColor
        self.codeBlockBackground = codeBlockBackground
        self.linkColor = linkColor
        self.quoteColor = quoteColor
        self.quoteBarColor = quoteBarColor
        self.tableBorderColor = tableBorderColor
        self.thematicBreakColor = thematicBreakColor
    }

    public func headingScale(for level: Int) -> Double {
        let index = min(max(level - 1, 0), headingScales.count - 1)
        return headingScales[index]
    }

    // MARK: Presets

    public static let light = MarkdownTheme(
        textColor: MDColor(gray: 0.13),
        markerColor: MDColor(gray: 0.62),
        headingColor: MDColor(red: 0.10, green: 0.10, blue: 0.14),
        strongColor: MDColor(gray: 0.08),
        emphasisColor: MDColor(gray: 0.16),
        strikethroughColor: MDColor(gray: 0.45),
        codeColor: MDColor(red: 0.72, green: 0.20, blue: 0.35),
        codeBackgroundColor: MDColor(red: 0.95, green: 0.94, blue: 0.94),
        codeBlockBackground: MDColor(red: 0.96, green: 0.96, blue: 0.97),
        linkColor: MDColor(red: 0.15, green: 0.45, blue: 0.90),
        quoteColor: MDColor(gray: 0.42),
        quoteBarColor: MDColor(red: 0.15, green: 0.45, blue: 0.90, alpha: 0.6),
        tableBorderColor: MDColor(gray: 0.80),
        thematicBreakColor: MDColor(gray: 0.78)
    )

    public static let dark = MarkdownTheme(
        textColor: MDColor(gray: 0.88),
        markerColor: MDColor(gray: 0.45),
        headingColor: MDColor(red: 0.96, green: 0.96, blue: 0.98),
        strongColor: MDColor(gray: 0.96),
        emphasisColor: MDColor(gray: 0.85),
        strikethroughColor: MDColor(gray: 0.55),
        codeColor: MDColor(red: 0.95, green: 0.55, blue: 0.60),
        codeBackgroundColor: MDColor(red: 0.17, green: 0.17, blue: 0.19),
        codeBlockBackground: MDColor(red: 0.12, green: 0.12, blue: 0.14),
        linkColor: MDColor(red: 0.42, green: 0.65, blue: 1.0),
        quoteColor: MDColor(gray: 0.58),
        quoteBarColor: MDColor(red: 0.42, green: 0.65, blue: 1.0, alpha: 0.6),
        tableBorderColor: MDColor(gray: 0.30),
        thematicBreakColor: MDColor(gray: 0.32)
    )
}
