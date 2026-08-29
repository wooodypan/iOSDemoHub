import UIKit
import MarkdownCore
import MPITextKit

/// Read-only markdown preview rendered asynchronously with MPITextKit.
///
/// Call `update(source:)` whenever the document changes; parsing and layout happen
/// in the background and the finished renderer is assigned on the main actor.
public final class MarkdownPreviewView: UIScrollView {

    public var theme: MarkdownTheme = .light {
        didSet { needsUpdate = true; setNeedsLayout() }
    }

    /// Content insets around the rendered document.
    public var contentInsets = UIEdgeInsets(top: 20, left: 16, bottom: 32, right: 16) {
        didSet { setNeedsLayout() }
    }

    public private(set) var source: String = ""

    private let label = MPILabel()
    private var generation = 0
    private var pendingTask: Task<Void, Never>?
    private var lastRenderedWidth: CGFloat = 0
    private var needsUpdate = true

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        label.displaysAsynchronously = true
        addSubview(label)
        backgroundColor = .systemBackground
    }

    /// Schedule a re-render of `source`; rapid calls are debounced and stale
    /// results are discarded.
    public func update(source newSource: String, immediately: Bool = false) {
        source = newSource
        generation += 1
        let currentGeneration = generation
        pendingTask?.cancel()

        let width = contentWidth
        let theme = self.theme
        pendingTask = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard !Task.isCancelled else { return }

            let result = await Task.detached(priority: .userInitiated) {
                PreviewRenderer.render(source: newSource, width: width, theme: theme)
            }.value

            guard let self, !Task.isCancelled, currentGeneration == self.generation else { return }
            self.apply(result, width: width)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentWidth
        guard width > 0 else { return }
        // Re-render when the column width changes (rotation, window resize) or when
        // a theme change was queued.
        if needsUpdate || abs(width - lastRenderedWidth) > 0.5 {
            needsUpdate = false
            update(source: source)
        }
    }

    private var contentWidth: CGFloat {
        max(0, bounds.width - contentInsets.left - contentInsets.right)
    }

    private func apply(_ result: PreviewRenderResult?, width: CGFloat) {
        guard let result else { return }
        lastRenderedWidth = width
        label.textRenderer = result.renderer
        label.frame = CGRect(x: contentInsets.left,
                             y: contentInsets.top,
                             width: result.size.width,
                             height: result.size.height)
        contentSize = CGSize(width: bounds.width,
                             height: result.size.height + contentInsets.top + contentInsets.bottom)
        flashScrollIndicators()
    }
}
