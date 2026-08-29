import UIKit
import MarkdownCore

/// Events surfaced to the hosting app.
@MainActor
public protocol MarkdownEditorDelegate: AnyObject {
    /// The plain markdown text changed (after editing or undo).
    func markdownEditorDidChangeText(_ editor: MarkdownEditorView)
}

@MainActor
public extension MarkdownEditorDelegate {
    func markdownEditorDidChangeText(_ editor: MarkdownEditorView) {}
}

/// A markdown source editor with AST-driven live highlighting.
///
/// The view edits plain markdown; styling is applied as attributes only, so copy/paste
/// always carries the raw source. Uses TextKit 1 explicitly — attribute-heavy batch
/// updates are far more reliable on the legacy layout manager.
public final class MarkdownEditorView: UITextView {

    public weak var markdownDelegate: MarkdownEditorDelegate?

    public var theme: MarkdownTheme {
        get { coordinator.theme }
        set {
            coordinator.theme = newValue
            coordinator.highlightNow(self)
        }
    }

    private let coordinator = HighlightCoordinator()
    private let bulletOverlay = ListBulletOverlay()
    /// Latest highlighted source; mirrors `text` once highlighting has caught up.
    private(set) public var highlightedSource: String = ""
    /// Marker ranges (`- `, `1. ` …) from the latest highlight pass.
    private var listMarkerRanges: [Range<Int>] = []

    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        forceTextKit1()
        commonInit()
    }

    public convenience init(frame: CGRect = .zero) {
        self.init(frame: frame, textContainer: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        forceTextKit1()
        commonInit()
    }

    /// UITextView defaults to TextKit 2; touching `layoutManager` makes UIKit fall
    /// back to TextKit 1 for this view. Batched attribute updates over large
    /// documents are far more reliable on the legacy layout manager. Must run
    /// before any text is set.
    private func forceTextKit1() {
        _ = layoutManager
    }

    private func commonInit() {
        delegate = self
        coordinator.didHighlight = { [weak self] source, markers in
            guard let self else { return }
            highlightedSource = source
            listMarkerRanges = markers
            setNeedsLayout()
        }
        autocorrectionType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        // Replace tabs on input so offsets match what cmark sees.
        keyboardType = .default
        font = UIFont.systemFont(ofSize: coordinator.theme.bodySize)
        // Extra left inset leaves a gutter where the list bullet overlay draws.
        textContainerInset = UIEdgeInsets(top: 16, left: 28, bottom: 24, right: 12)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateListBullets()
    }

    /// Position the bullet overlay; bullets hide while the text is ahead of the
    /// last highlight pass so they never point at stale offsets.
    private func updateListBullets() {
        let source = text ?? ""
        let settled = source == coordinator.lastAppliedText && markedTextRange == nil
        let markers = settled ? unorderedListMarkers(source) : []
        bulletOverlay.update(textView: self,
                             markerRanges: markers,
                             color: UIColor(coordinator.theme.linkColor))
    }

    /// Unordered list markers only: `- `, `* `, `+ `. Ordered items (`1. `) are skipped.
    private func unorderedListMarkers(_ source: String) -> [Range<Int>] {
        let utf16 = Array(source.utf16)
        return listMarkerRanges.filter { range in
            guard range.lowerBound < utf16.count else { return false }
            switch utf16[range.lowerBound] {
            case 0x2D, 0x2A, 0x2B: return true // "-", "*", "+"
            default: return false
            }
        }
    }

    /// Apply the theme and re-highlight immediately.
    public func setTheme(_ theme: MarkdownTheme) {
        self.theme = theme
    }

    /// Re-highlight synchronously (e.g. after programmatically replacing the text).
    public func rehighlight() {
        coordinator.highlightNow(self)
    }
}

extension MarkdownEditorView: UITextViewDelegate {

    public func textView(_ textView: UITextView,
                         shouldChangeTextIn range: NSRange,
                         replacementText text: String) -> Bool {
        guard text.contains("\r") || text.contains("\t") else { return true }
        // Normalize CRLF/CR/tabs manually so the displayed text is exactly what the
        // parser sees.
        let normalized = MDText.normalize(text)
        textView.textStorage.replaceCharacters(in: range, with: normalized)
        let newLocation = range.location + (normalized as NSString).length
        textView.selectedRange = NSRange(location: newLocation, length: 0)
        coordinator.scheduleHighlight(for: textView)
        markdownDelegate?.markdownEditorDidChangeText(self)
        return false
    }

    public func textViewDidChange(_ textView: UITextView) {
        coordinator.scheduleHighlight(for: textView)
        markdownDelegate?.markdownEditorDidChangeText(self)
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        // Keep the caret from inheriting heading/code attributes; input is always
        // plain body style.
        textView.typingAttributes = TokenAttributes(theme: coordinator.theme).baseAttributes
        // Selection changes also fire after undo, which does not trigger
        // textViewDidChange — reschedule only when the text is dirty so ordinary
        // caret movement does not reparse.
        if (textView.text ?? "") != coordinator.lastAppliedText {
            coordinator.scheduleHighlight(for: textView)
        }
    }
}
