import UIKit
import MarkdownCore
import MarkdownEditor
import MarkdownPreview

/// Demo shell: segmented switch between the editor, the MPITextKit preview and an
/// AST inspector that shows the swift-markdown tree of the current document.
final class MarkdownEditorViewController: UIViewController {

    private enum Mode: Int {
        case edit = 0, preview, ast

        init?(name: String) {
            switch name {
            case "edit": self = .edit
            case "preview": self = .preview
            case "ast": self = .ast
            default: return nil
            }
        }
    }

    private let editor = MarkdownEditorView()
    private let preview = MarkdownPreviewView()
    private let astView = UITextView()
    private let modeControl = UISegmentedControl(items: ["编辑", "预览", "AST"])
    private var mode: Mode = .edit
    private var darkTheme = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Markdown 编辑器"
        view.backgroundColor = .systemBackground

        setupEditor()
        setupPreview()
        setupASTView()
        setupNavigationItems()

        editor.text = SampleDocument.text
        editor.rehighlight()
        preview.update(source: SampleDocument.text)

        let args = ProcessInfo.processInfo.arguments
        if let flagIndex = args.firstIndex(of: "-mode"),
           flagIndex + 1 < args.count,
           let launchMode = Mode(name: args[flagIndex + 1]) {
            modeControl.selectedSegmentIndex = launchMode.rawValue
            modeChanged()
        }
        if let themeIndex = args.firstIndex(of: "-theme"),
           themeIndex + 1 < args.count, args[themeIndex + 1] == "dark" {
            toggleTheme()
        }
        if args.contains("-perf") {
            runPerfBenchmark()
        }
    }

    /// Console benchmark for large documents (launch with `-perf`).
    private func runPerfBenchmark() {
        func bench(_ label: String, _ body: () -> Void) {
            let start = CACurrentMediaTime()
            body()
            let ms = (CACurrentMediaTime() - start) * 1000
            print("[PERF] \(label): \(String(format: "%.1f", ms)) ms")
        }

        let chunk = SampleDocument.text
        func grow(to target: Int) -> String {
            var doc = ""
            while doc.count < target { doc += chunk + "\n\n" }
            return doc
        }

        for (label, doc) in [("10k", grow(to: 10_000)), ("100k", grow(to: 100_000))] {
            print("[PERF] document \(label): \(doc.count) characters")
            bench("styleOps \(label)") { _ = MarkdownPipeline.styleOps(for: doc) }
            bench("rendered \(label)") { _ = MarkdownPipeline.rendered(from: doc) }
            bench("preview render \(label)") {
                _ = PreviewRenderer.render(source: doc, width: 360, theme: .light)
            }
        }
    }

    // MARK: - Setup

    private func setupEditor() {
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.markdownDelegate = self
        editor.theme = .light
        view.addSubview(editor)
        pin(editor)
    }

    private func setupPreview() {
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.isHidden = true
        preview.theme = .light
        view.addSubview(preview)
        pin(preview)
    }

    private func setupASTView() {
        astView.translatesAutoresizingMaskIntoConstraints = false
        astView.isHidden = true
        astView.isEditable = false
        astView.isSelectable = true
        astView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        astView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 24, right: 8)
        astView.backgroundColor = .secondarySystemBackground
        view.addSubview(astView)
        pin(astView)
    }

    private func setupNavigationItems() {
        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        navigationItem.titleView = modeControl

        let themeItem = UIBarButtonItem(image: UIImage(systemName: "moon"),
                                        style: .plain,
                                        target: self,
                                        action: #selector(toggleTheme))
        navigationItem.rightBarButtonItem = themeItem
    }

    private func pin(_ child: UIView) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        guard let mode = Mode(rawValue: modeControl.selectedSegmentIndex) else { return }
        self.mode = mode
        editor.isHidden = mode != .edit
        preview.isHidden = mode != .preview
        astView.isHidden = mode != .ast
        if mode == .preview {
            preview.update(source: editor.text ?? "")
        } else if mode == .ast {
            refreshAST()
        }
    }

    @objc private func toggleTheme() {
        darkTheme.toggle()
        let theme: MarkdownTheme = darkTheme ? .dark : .light
        editor.theme = theme
        preview.theme = theme
        astView.backgroundColor = darkTheme ? .black : .secondarySystemBackground
        astView.textColor = darkTheme ? .white : .label
        overrideUserInterfaceStyle = darkTheme ? .dark : .light
        navigationItem.rightBarButtonItem?.image = UIImage(systemName: darkTheme ? "sun.min" : "moon")
        if mode == .preview {
            preview.update(source: editor.text ?? "")
        }
    }

    private func refreshAST() {
        let document = MarkdownPipeline.parse(editor.text ?? "")
        astView.text = MarkdownPipeline.dump(document)
    }
}

extension MarkdownEditorViewController: MarkdownEditorDelegate {

    func markdownEditorDidChangeText(_ editorView: MarkdownEditorView) {
        let source = editorView.text ?? ""
        preview.update(source: source)
        if mode == .ast {
            refreshAST()
        }
    }
}
