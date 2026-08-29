import UIKit
import MarkdownCore

/// Debounced background parsing + main-thread attribute application for a markdown
/// `UITextView`. The plain text content is never touched: only attributes change.
@MainActor
final class HighlightCoordinator: NSObject {

    var theme: MarkdownTheme = .light
    /// Called after highlighting finishes (used to refresh dependent views).
    /// The second value holds the `- `/`1. ` marker ranges of every list item.
    var didHighlight: ((_ text: String, _ listMarkers: [Range<Int>]) -> Void)?

    private var generation = 0
    private var pendingTask: Task<Void, Never>?
    /// Debounce window for re-highlighting after edits.
    private let debounceInterval: Duration = .milliseconds(120)
    /// The source string that currently has highlighting applied.
    private(set) var lastAppliedText: String = ""

    // MARK: - Scheduling

    func scheduleHighlight(for textView: UITextView) {
        generation += 1
        let currentGeneration = generation
        pendingTask?.cancel()

        let source = textView.text ?? ""
        pendingTask = Task { [weak textView, weak self] in
            try? await Task.sleep(for: self?.debounceInterval ?? .milliseconds(120))
            guard !Task.isCancelled else { return }

            // Parse off the main thread; only Sendable values cross the boundary.
            let output = await Task.detached(priority: .userInitiated) {
                MarkdownPipeline.styleOps(for: source)
            }.value

            guard let self, let textView, !Task.isCancelled else { return }
            guard currentGeneration == self.generation else { return }
            // Discard stale results: the text changed while we were parsing.
            guard MDText.normalize(textView.text ?? "") == output.text else { return }

            self.apply(output.ops, to: textView)
            self.didHighlight?(output.text, Self.listMarkerRanges(in: output.ops))
        }
    }

    /// Immediate highlight without debounce (initial load, theme changes).
    func highlightNow(_ textView: UITextView) {
        generation += 1
        let output = MarkdownPipeline.styleOps(for: textView.text ?? "")
        textView.text = output.text
        apply(output.ops, to: textView)
        didHighlight?(output.text, Self.listMarkerRanges(in: output.ops))
    }

    private static func listMarkerRanges(in ops: [StyleOp]) -> [Range<Int>] {
        ops.compactMap { op in
            if case .marker(.list) = op.token { return op.range }
            return nil
        }
    }

    // MARK: - Application

    private func apply(_ ops: [StyleOp], to textView: UITextView) {
        // Never re-style while an input method is composing (e.g. Chinese pinyin).
        guard textView.markedTextRange == nil else { return }

        let storage = textView.textStorage
        let selectedRange = textView.selectedRange
        let materializer = TokenAttributes(theme: theme)

        storage.beginEditing()
        storage.setAttributes(materializer.baseAttributes,
                              range: NSRange(location: 0, length: storage.length))
        for op in ops {
            let range = NSRange(location: op.range.lowerBound, length: op.range.count)
            guard range.location >= 0, NSMaxRange(range) <= storage.length else { continue }
            materializer.apply(op.token, range: range, in: storage)
        }
        storage.endEditing()

        // Restore the caret; clamp so it can never fall outside the text.
        let location = min(selectedRange.location, storage.length)
        let length = min(selectedRange.length, storage.length - location)
        textView.selectedRange = NSRange(location: location, length: length)
        lastAppliedText = textView.text ?? ""
    }
}
