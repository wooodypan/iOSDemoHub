import Foundation
import Markdown

/// End-to-end markdown processing built on swift-markdown.
public enum MarkdownPipeline {

    /// The result of the highlight pipeline: safe to send across concurrency domains.
    public struct StyleOutput: Sendable {
        /// The normalized source (the exact string the ops refer to).
        public let text: String
        /// Priority-ordered style operations.
        public let ops: [StyleOp]
    }

    /// Normalize, parse and style markdown source. Runs the full cmark parse and is
    /// designed to be called off the main thread.
    public static func styleOps(for source: String) -> StyleOutput {
        let text = MDText.normalize(source)
        let document = Document(parsing: text)
        let map = UTF16LineMap(source: text)
        var styler = MarkdownStyler(map: map)
        return StyleOutput(text: text, ops: styler.styleOps(for: document))
    }

    /// Parse markdown source into a swift-markdown AST (for debugging / inspection).
    public static func parse(_ source: String) -> Document {
        Document(parsing: MDText.normalize(source))
    }

    /// Multi-line structural dump of an AST, e.g. for an inspector panel.
    public static func dump(_ markup: Markup) -> String {
        markup.debugDescription(options: [.printSourceLocations])
    }
}
