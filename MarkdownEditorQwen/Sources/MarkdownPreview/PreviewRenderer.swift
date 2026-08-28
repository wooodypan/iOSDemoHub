import UIKit
import MarkdownCore
import MPITextKit

/// A fully laid-out preview, safe to build off the main thread and hand back.
public struct PreviewRenderResult: @unchecked Sendable {
    public let renderer: MPITextRenderer
    public let size: CGSize
}

/// Builds `MPITextRenderer`s from markdown source entirely off the main thread:
/// parse → strip markers → attribute materialization → TextKit layout all happen
/// here, so the main thread only assigns the finished renderer.
public enum PreviewRenderer {

    public static func render(source: String,
                              width: CGFloat,
                              theme: MarkdownTheme) -> PreviewRenderResult? {
        guard width > 0 else { return nil }
        let rendered = MarkdownPipeline.rendered(from: source)
        let attributed = PreviewAttributedBuilder.attributedString(for: rendered, theme: theme)

        let builder = MPITextRenderAttributesBuilder()
        builder.attributedText = attributed
        // Defaults are single-line tail truncation — must override for documents.
        builder.lineBreakMode = .byWordWrapping
        builder.maximumNumberOfLines = 0
        let attributes = builder.build()

        let renderer = MPITextRenderer(renderAttributes: attributes,
                                       constrainedSize: CGSize(width: width,
                                                               height: .greatestFiniteMagnitude))
        return PreviewRenderResult(renderer: renderer, size: renderer.size())
    }
}
