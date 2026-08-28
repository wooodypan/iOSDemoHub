import UIKit
import MPITextKit

/// Block background that expands to cover the whole character range instead of
/// drawing one rounded rect per line, giving code blocks a single panel look.
public final class MPICodeBlockBackground: MPITextBackground {

    public override func backgroundRect(for textContainer: NSTextContainer,
                                        proposedRect: CGRect,
                                        characterRange: NSRange) -> CGRect {
        var rect = super.backgroundRect(for: textContainer,
                                        proposedRect: proposedRect,
                                        characterRange: characterRange)
        guard let layoutManager = textContainer.layoutManager else { return rect }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange,
                                                   actualCharacterRange: nil)
        let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange,
                                                  in: textContainer)
        // Union with the proposed rect so negative insets still widen the panel.
        rect = bounding.union(rect)
        return CGRectInset(rect, insets.left, insets.top)
    }
}

/// Thin vertical bar drawn at the leading edge of every line of a block quote.
public final class MPIQuoteBarBackground: MPITextBackground {

    public var barWidth: CGFloat = 3

    public init(barColor: UIColor, barWidth: CGFloat = 3) {
        self.barWidth = barWidth
        super.init()
        fillColor = barColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func backgroundRect(for textContainer: NSTextContainer,
                                        proposedRect: CGRect,
                                        characterRange: NSRange) -> CGRect {
        let rect = super.backgroundRect(for: textContainer,
                                        proposedRect: proposedRect,
                                        characterRange: characterRange)
        return CGRect(x: rect.minX, y: rect.minY, width: barWidth, height: rect.height)
    }
}
