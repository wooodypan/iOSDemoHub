import UIKit

// MARK: - DetailViewController
// 详情页：展示文章内容，提供“在新Tab打开”和“在新窗口打开”按钮。
// 新增“备注输入框”示例：输入文字后，本控制器的 Bool 属性 isEdited 会变为 true，
// 并通过 onEditStateChanged 回调通知父控制器（比如把当前 Tab 固定为正式 Tab）。
class DetailViewController: UIViewController {

    var onOpenNewTab: ((Article) -> Void)?
    var onOpenNewWindow: ((Article) -> Void)?

    // 当备注输入框内容发生变化时回调：
    //   true  = 用户输入了内容（用于把当前 Tab 固定为正式 Tab）
    //   false = 输入框被清空
    var onEditStateChanged: ((Bool) -> Void)?

    // 关键 Bool 属性：记录用户是否在备注框里输入过内容。
    // 这是“某个 UIViewController 的某个 Bool 值属性”，输入文字后它就变成 true。
    var isEdited: Bool = false

    private var currentArticle: Article?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let titleLabel = UILabel()
    private let categoryLabel = UILabel()
    private let bodyLabel = UILabel()
    private let placeholderLabel = UILabel()

    // 备注区：一个标签 + 一个输入框
    private let noteLabel = UILabel()
    private let noteTextField = UITextField()
    // 标记是否正在由 configure 做“程序化重置”，此时不要触发编辑回调
    private var isResetting: Bool = false

    private var actionStackView: UIStackView!

    // 重写父类的指定初始化方法（与之前一致，保证 DetailViewController() 可用）。
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    // 便捷初始化：可以传入一篇文章（可选），方便外部直接创建并展示内容。
    convenience init(article: Article? = nil) {
        self.init(nibName: nil, bundle: nil)
        self.currentArticle = article
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupViews()
    }

    // MARK: - Setup

    private func setupViews() {
        // ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        // Category
        categoryLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        categoryLabel.textColor = .systemBlue
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false

        // Title
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Body
        bodyLabel.font = UIFont.systemFont(ofSize: 15)
        bodyLabel.numberOfLines = 0
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        // 备注标签
        noteLabel.text = "我的备注（输入内容后，当前 Tab 会被固定为正式 Tab）"
        noteLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        noteLabel.textColor = .secondaryLabel
        noteLabel.numberOfLines = 0
        noteLabel.translatesAutoresizingMaskIntoConstraints = false

        // 备注输入框
        noteTextField.placeholder = "在这里输入…"
        noteTextField.borderStyle = .roundedRect
        noteTextField.font = UIFont.systemFont(ofSize: 15)
        noteTextField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        noteTextField.translatesAutoresizingMaskIntoConstraints = false

        // Action buttons
        let newTabButton = makeActionButton(title: "在新 Tab 中打开", systemImage: "plus.rectangle.on.rectangle", action: #selector(openNewTab))
        let newWindowButton = makeActionButton(title: "在新窗口中打开", systemImage: "rectangle.on.rectangle.angled", action: #selector(openNewWindow))
        actionStackView = UIStackView(arrangedSubviews: [newTabButton, newWindowButton])
        actionStackView.axis = .horizontal
        actionStackView.spacing = 12
        actionStackView.distribution = .fillEqually
        actionStackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(categoryLabel)
        contentView.addSubview(titleLabel)
        contentView.addSubview(bodyLabel)
        contentView.addSubview(noteLabel)
        contentView.addSubview(noteTextField)
        contentView.addSubview(actionStackView)

        NSLayoutConstraint.activate([
            categoryLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            categoryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            categoryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            titleLabel.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            bodyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            bodyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            noteLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 24),
            noteLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            noteLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            noteTextField.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 8),
            noteTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            noteTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            noteTextField.heightAnchor.constraint(equalToConstant: 40),

            actionStackView.topAnchor.constraint(equalTo: noteTextField.bottomAnchor, constant: 24),
            actionStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            actionStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            actionStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            actionStackView.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Placeholder
        placeholderLabel.text = "← 请从左侧选择文章"
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.font = UIFont.systemFont(ofSize: 18)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        updateVisibility(hasArticle: false)
    }

    private func makeActionButton(title: String, systemImage: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        if #available(iOS 13.0, *) {
            button.setImage(UIImage(systemName: systemImage), for: .normal)
        }
        button.backgroundColor = .systemBlue
        button.tintColor = .white
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func updateVisibility(hasArticle: Bool) {
        placeholderLabel.isHidden = hasArticle
        scrollView.isHidden = !hasArticle
    }

    // MARK: - 备注输入框变化

    // 输入框内容变化时被调用（.editingChanged 事件）。
    @objc private func textChanged() {
        // 如果是 configure 在做程序化清空，则忽略，不触发编辑回调
        guard !isResetting else { return }

        let hasText = !(noteTextField.text ?? "").isEmpty
        // 关键：输入文字 -> isEdited 变为 true；清空 -> 变回 false
        isEdited = hasText
        // 通知父控制器（例如把当前 Tab 固定为正式 Tab）
        onEditStateChanged?(hasText)
    }

    // MARK: - Configure

    func configure(with article: Article) {
        currentArticle = article
        categoryLabel.text = article.category.uppercased()
        titleLabel.text = article.title
        bodyLabel.text = article.body
        title = article.title
        updateVisibility(hasArticle: true)

        // 切换文章时，把备注框重置为空（程序化重置，不触发编辑回调）
        isResetting = true
        noteTextField.text = ""
        isResetting = false
        isEdited = false

        // iPhone 下，"新Tab"/"新窗口"按钮隐藏（无意义）
        actionStackView.isHidden = (DeviceHelper.currentLayout == .iPhone)
    }

    // MARK: - Actions

    @objc private func openNewTab() {
        guard let article = currentArticle else { return }
        onOpenNewTab?(article)
    }

    @objc private func openNewWindow() {
        guard let article = currentArticle else { return }
        onOpenNewWindow?(article)
    }
}
