import UIKit

// MARK: - 单个详情 Tab 的数据
// 模仿 NewsSplitDemo 的 DetailTabItem：每个 tab 记录 id、对应的文章、持有的 DetailViewController，
// 以及它是否为“预览 Tab”（可复用）。
private struct DetailTabItem {
    let id: String
    var article: Article?
    let controller: DetailViewController
    var isPreview: Bool
}

// MARK: - DetailHostViewController
// 模仿 NewsSplitDemo 的 DetailHostViewController，但每个 Tab 是咱们的 DetailViewController，
// 并实现 VS Code 的“复用 Tab 策略”：
//   - preview（单击）：复用已有的“预览 Tab”；没有则新建一个预览 Tab。
//   - newTab（双击 / “新Tab打开”）：永远新建正式 Tab，不复用。
//   - 在详情里点击“标记为已编辑”：把当前 Tab 固定为正式 Tab（不再被预览复用覆盖）。
// 多 Tab 的本质是：多个 DetailViewController 作为子控制器保活（addChild），切换时只隐藏/显示。
final class DetailHostViewController: UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout {

    // 内容容器：当前激活的 DetailViewController 显示在这里。
    private let contentContainerView = UIView()
    // 没有 Tab 时显示的占位文案。
    private let placeholderLabel = UILabel()
    // Tab 条与内容之间的分隔线。
    private let separatorView = UIView()

    private lazy var collectionViewLayout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = 8
        return layout
    }()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = UIColor(white: 0.97, alpha: 1.0)
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(DetailTabCell.self, forCellWithReuseIdentifier: DetailTabCell.reuseIdentifier)
        return collectionView
    }()

    // 所有 Tab（强引用子控制器即实现“保活”）。
    private var tabs: [DetailTabItem] = []
    private var selectedTabID: String?

    // 高度约束，方便在没有 Tab 时把 Tab 条收起。
    private var collectionViewHeightConstraint: NSLayoutConstraint?
    private var separatorHeightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupViews()
        refreshUI()
    }

    // MARK: - 对外的“打开文章”入口（由 router 调用）

    /// 预览（单击）：复用已有的预览 Tab；没有则新建一个预览 Tab。
    func openPreview(_ article: Article) {
        if let index = tabs.firstIndex(where: { $0.isPreview }) {
            // 复用预览槽位：把文章加载进去并切过去。
            load(article: article, into: index)
            selectedTabID = tabs[index].id
            refreshUI()
        } else {
            // 没有预览 Tab（当前都是正式 Tab）-> 新建一个预览 Tab。
            appendTab(for: article, isPreview: true)
        }
    }

    /// 正式 Tab（双击 / 在详情里点“新Tab打开”）：永远新建，不复用。
    func openNewTab(_ article: Article? = nil) {
        appendTab(for: article, isPreview: false)
    }

    /// 兼容 NewsSplitDemo 式 mode 分发（router 直接调这个即可）。
    func openArticle(_ item: Article, mode: ArticleOpenMode) {
        switch mode {
        case .preview:
            openPreview(item)
        case .newTab:
            openNewTab(item)
        case .newWindow:
            // 新窗口由 router 层决定，这里兜底也处理一下。
            WindowManager.openNewWindow(article: item)
        }
    }

    // MARK: - UICollectionView 数据源 / 代理

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        tabs.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: DetailTabCell.reuseIdentifier,
            for: indexPath
        ) as? DetailTabCell else {
            return UICollectionViewCell()
        }

        let tab = tabs[indexPath.item]
        cell.configure(
            title: tab.article?.title ?? "New Tab",
            selected: tab.id == selectedTabID,
            isPreview: tab.isPreview
        )
        cell.onClose = { [weak self] in
            self?.closeTab(withID: tab.id)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedTabID = tabs[indexPath.item].id
        refreshUI()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let title = (tabs[indexPath.item].article?.title ?? "New Tab") as NSString
        let width = title.size(withAttributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
        ]).width
        return CGSize(width: min(max(width + 46, 120), 240), height: 34)
    }

    // MARK: - 私有：Tab 管理

    private func load(article: Article, into index: Int) {
        tabs[index].article = article
        tabs[index].controller.configure(with: article)
        // 载入新文章时把编辑状态复位（configure 内部也会复位 isEdited）。
        tabs[index].controller.isEdited = false
    }

    private func appendTab(for article: Article?, isPreview: Bool) {
        let controller = DetailViewController()
        if let article = article {
            controller.configure(with: article)
        }

        // 详情里“标记为已编辑” -> 把当前这个 Tab 固定为正式 Tab（不再被预览复用）。
        controller.onEditStateChanged = { [weak self, weak controller] pinned in
            guard let self, let controller else { return }
            self.setPreview(!pinned, for: controller)
        }
        // 详情里“在新Tab打开” -> 由宿主新建一个正式 Tab。
        controller.onOpenNewTab = { [weak self] article in
            self?.openNewTab(article)
        }
        // 详情里“在新窗口打开” -> 交给 WindowManager。
        controller.onOpenNewWindow = { article in
            WindowManager.openNewWindow(article: article)
        }

        let tabID = UUID().uuidString

        // 作为子控制器保活。
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor)
        ])
        controller.didMove(toParent: self)

        tabs.append(DetailTabItem(id: tabID, article: article, controller: controller, isPreview: isPreview))
        selectedTabID = tabID
        refreshUI()
    }

    private func closeTab(withID id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let tab = tabs.remove(at: index)
        tab.controller.willMove(toParent: nil)
        tab.controller.view.removeFromSuperview()
        tab.controller.removeFromParent()

        if tabs.isEmpty {
            selectedTabID = nil
        } else if selectedTabID == id {
            // 关掉的是当前 Tab，则切到相邻的那个。
            let nextIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[nextIndex].id
        }

        refreshUI()
    }

    // 把某个 Tab 设为预览/正式，并刷新对应 cell 的样式。
    private func setPreview(_ value: Bool, for controller: DetailViewController) {
        guard let index = tabs.firstIndex(where: { $0.controller === controller }) else { return }
        tabs[index].isPreview = value
        collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
    }

    // MARK: - 私有：视图与刷新

    private func setupViews() {
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = UIColor(white: 0.87, alpha: 1.0)

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.backgroundColor = .white

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = "← 请从左侧选择文章"
        placeholderLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        placeholderLabel.textColor = .tertiaryLabel

        view.addSubview(collectionView)
        view.addSubview(separatorView)
        view.addSubview(contentContainerView)
        contentContainerView.addSubview(placeholderLabel)

        let collectionViewHeightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 44)
        let separatorHeightConstraint = separatorView.heightAnchor.constraint(equalToConstant: 1)
        self.collectionViewHeightConstraint = collectionViewHeightConstraint
        self.separatorHeightConstraint = separatorHeightConstraint

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            collectionViewHeightConstraint,

            separatorView.topAnchor.constraint(equalTo: collectionView.bottomAnchor),
            separatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separatorHeightConstraint,

            contentContainerView.topAnchor.constraint(equalTo: separatorView.bottomAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            placeholderLabel.centerXAnchor.constraint(equalTo: contentContainerView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor)
        ])
    }

    private func refreshUI() {
        let hasTabs = !tabs.isEmpty
        collectionView.isHidden = !hasTabs
        separatorView.isHidden = !hasTabs
        placeholderLabel.isHidden = hasTabs
        collectionViewHeightConstraint?.constant = hasTabs ? 44 : 0
        separatorHeightConstraint?.constant = hasTabs ? 1 : 0

        for tab in tabs {
            let isSelected = tab.id == selectedTabID
            tab.controller.view.isHidden = !isSelected
            if isSelected {
                contentContainerView.bringSubviewToFront(tab.controller.view)
            }
        }

        collectionView.reloadData()

        if let selectedIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) {
            let indexPath = IndexPath(item: selectedIndex, section: 0)
            DispatchQueue.main.async { [weak self] in
                self?.collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
            }
        }
    }
}

// MARK: - DetailTabCell
// 模仿 NewsSplitDemo 的 DetailTabCell：一个 tab 标题 + 关闭按钮。
// 预览 Tab 用斜体强调“可复用”，正式 Tab 用正常字体。
private final class DetailTabCell: UICollectionViewCell {
    static let reuseIdentifier = "DetailTabCell"

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        contentView.layer.cornerRadius = 8
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor(white: 0.80, alpha: 1.0).cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .black
        titleLabel.lineBreakMode = .byTruncatingTail

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("x", for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        contentView.addSubview(titleLabel)
        contentView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),

            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    func configure(title: String, selected: Bool, isPreview: Bool) {
        titleLabel.text = title
        contentView.backgroundColor = selected ? UIColor(white: 0.89, alpha: 1.0) : UIColor(white: 0.96, alpha: 1.0)
        // 预览 Tab 用斜体，强调“可复用”；正式 Tab 用正常字体（半粗）。
        titleLabel.font = isPreview
            ? UIFont.italicSystemFont(ofSize: 14)
            : UIFont.systemFont(ofSize: 14, weight: .semibold)
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
