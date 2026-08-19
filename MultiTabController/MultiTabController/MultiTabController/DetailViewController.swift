import UIKit

// MARK: - DetailViewController
// 详情页：展示文章内容，提供"在新Tab打开"和"在新窗口打开"按钮
class DetailViewController: UIViewController {

    var onOpenNewTab: ((Article) -> Void)?
    var onOpenNewWindow: ((Article) -> Void)?

    private var currentArticle: Article?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let titleLabel = UILabel()
    private let categoryLabel = UILabel()
    private let bodyLabel = UILabel()
    private let placeholderLabel = UILabel()
    private var actionStackView: UIStackView!

//重写init方法
init(article: Article? = nil) {
    super.init(nibName: nil, bundle: nil)
    currentArticle = article
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

            actionStackView.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 32),
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

    // MARK: - Configure

    func configure(with article: Article) {
        currentArticle = article
        categoryLabel.text = article.category.uppercased()
        titleLabel.text = article.title
        bodyLabel.text = article.body
        title = article.title
        updateVisibility(hasArticle: true)

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
