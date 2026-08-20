import UIKit

// MARK: - BrowserTab 数据模型
class BrowserTab {
    let id: UUID
    var title: String
    // 保活的 SplitViewController（持有强引用即保活）
    let splitVC: CustomSplitViewController
    // 是否为“预览 Tab”（可复用）。false 表示正式 Tab（不复用）。
    var isPreview: Bool

    init(title: String, splitVC: CustomSplitViewController, isPreview: Bool = true) {
        self.id = UUID()
        self.title = title
        self.splitVC = splitVC
        self.isPreview = isPreview
    }
}

// MARK: - BrowserTabManagerViewController
// iPad/Mac 上的多 Tab 容器，顶部是 Tab 栏，下方是内容区。
// 这里实现 VS Code 的“复用 Tab 策略”：
//   - 单击文章 = 预览：复用已有的 Preview Tab；没有则新建一个 Preview Tab。
//   - 双击文章 / “在新Tab打开” = 正式 Tab：永远新建，且不会被后续单击替换。
//   - 在详情里输入备注（编辑） = 把当前 Preview Tab 固定为正式 Tab，之后再单击就会新建而不是覆盖。
class BrowserTabManagerViewController: UIViewController {

    private var tabs: [BrowserTab] = []
    private var activeTabIndex: Int = 0

    // 顶部 Tab 栏（用 UICollectionView 实现）
    private var tabBarCollectionView: UICollectionView!
    private let tabBarHeight: CGFloat = 44

    // 内容容器：当前激活的 SplitViewController 放这里
    private let contentContainerView = UIView()
    private var currentChildVC: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupTabBarCollectionView()
        setupContentContainer()
        // 启动时先建一个空的 Preview Tab（可被首次单击复用）
        openNewTab(article: nil, isPreview: true, animated: false)
    }

    // MARK: - Setup

    private func setupTabBarCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        layout.estimatedItemSize = CGSize(width: 160, height: 36)

        tabBarCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        tabBarCollectionView.translatesAutoresizingMaskIntoConstraints = false
        tabBarCollectionView.backgroundColor = .systemGroupedBackground
        tabBarCollectionView.showsHorizontalScrollIndicator = false
        tabBarCollectionView.dataSource = self
        tabBarCollectionView.delegate = self
        tabBarCollectionView.register(TabBarCell.self, forCellWithReuseIdentifier: TabBarCell.reuseId)

        view.addSubview(tabBarCollectionView)
        NSLayoutConstraint.activate([
            tabBarCollectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabBarCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 222),
            tabBarCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarCollectionView.heightAnchor.constraint(equalToConstant: tabBarHeight)
        ])
    }

    private func setupContentContainer() {
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainerView)
        NSLayoutConstraint.activate([
            contentContainerView.topAnchor.constraint(equalTo: tabBarCollectionView.bottomAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Tab Management

    /// 打开一个新 Tab。
    /// - parameter isPreview: true=预览 Tab（可复用）；false=正式 Tab（不复用）。
    func openNewTab(article: Article?, isPreview: Bool = true, animated: Bool = true) {
        let splitVC = makeSplitViewController(initialArticle: article)
        let title = article?.title ?? "New Tab"
        let tab = BrowserTab(title: title, splitVC: splitVC, isPreview: isPreview)
        tabs.append(tab)
        let newIndex = tabs.count - 1
        switchToTab(at: newIndex, animated: animated)
        tabBarCollectionView.reloadData()
        // 滚动到最新 tab
        let ip = IndexPath(item: newIndex, section: 0)
        tabBarCollectionView.scrollToItem(at: ip, at: .right, animated: animated)
    }

    func closeTab(at index: Int) {
        guard tabs.count > 1 else { return } // 至少保留一个 Tab
        tabs.remove(at: index)
        let newIndex = min(activeTabIndex, tabs.count - 1)
        switchToTab(at: newIndex, animated: false)
        tabBarCollectionView.reloadData()
    }

    func switchToTab(at index: Int, animated: Bool = true) {
        guard index >= 0, index < tabs.count else { return }
        activeTabIndex = index

        let newVC = tabs[index].splitVC

        // 移除旧的子 VC
        if let current = currentChildVC {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }

        // 添加新的子 VC
        addChild(newVC)
        newVC.view.frame = contentContainerView.bounds
        newVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentContainerView.addSubview(newVC.view)
        newVC.didMove(toParent: self)
        currentChildVC = newVC

        tabBarCollectionView.reloadData()
    }

    private func makeSplitViewController(initialArticle: Article?) -> CustomSplitViewController {
        let splitVC = CustomSplitViewController()

        // 左侧列表“单击” -> 预览策略（复用/新建 Preview Tab）
        splitVC.onArticlePreviewSelected = { [weak self] article in
            self?.handleArticlePreviewSelected(article)
        }
        // 左侧列表“双击” -> 正式打开（永远新建正式 Tab）
        splitVC.onArticleOpenSelected = { [weak self] article in
            self?.openNewTab(article: article, isPreview: false)
        }
        // “在新 Tab 中打开”按钮 -> 新建正式 Tab
        splitVC.onOpenNewTab = { [weak self] article in
            self?.openNewTab(article: article, isPreview: false)
        }
        splitVC.onOpenNewWindow = { article in
            // 打开新窗口（在 Mac Catalyst / iPadOS 13+ 支持多窗口时可用）
            WindowManager.openNewWindow(article: article)
        }
        // 详情备注被编辑 -> 把当前这个分屏对应的 Tab 固定为正式 Tab
        splitVC.onTabPinned = { [weak self, weak splitVC] pinned in
            guard let self, let splitVC else { return }
            if let idx = self.tabs.firstIndex(where: { $0.splitVC === splitVC }) {
                self.tabs[idx].isPreview = !pinned
                self.tabBarCollectionView.reloadItems(at: [IndexPath(item: idx, section: 0)])
            }
        }

        if let article = initialArticle {
            // 延迟一帧让 splitVC 完成布局后再设置详情
            DispatchQueue.main.async {
                splitVC.showDetail(article: article)
            }
        }
        return splitVC
    }

    // MARK: - 预览策略核心

    /// 单击文章时的处理（对应 VS Code 的 Preview Tab）：
    /// 若已存在 Preview Tab，则复用它（加载文章 + 切过去）；否则新建一个 Preview Tab。
    private func handleArticlePreviewSelected(_ article: Article) {
        if let previewIdx = tabs.firstIndex(where: { $0.isPreview }) {
            // 复用已有的 Preview Tab
            tabs[previewIdx].splitVC.showDetail(article: article)
            tabs[previewIdx].title = article.title
            switchToTab(at: previewIdx)
        } else {
            // 没有 Preview Tab（当前都是正式 Tab）-> 新建一个 Preview Tab
            openNewTab(article: article, isPreview: true)
        }
    }

    /// 从外部更新当前激活 tab 的标题（当用户在左侧选中文章时）
    func updateActiveTabTitle(_ title: String) {
        guard activeTabIndex < tabs.count else { return }
        tabs[activeTabIndex].title = title
        tabBarCollectionView.reloadItems(at: [IndexPath(item: activeTabIndex, section: 0)])
    }
}

// MARK: - UICollectionViewDataSource & Delegate
extension BrowserTabManagerViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tabs.count + 1 // 最后一个是"+"按钮
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TabBarCell.reuseId, for: indexPath) as! TabBarCell
        if indexPath.item < tabs.count {
            let tab = tabs[indexPath.item]
            let isActive = indexPath.item == activeTabIndex
            cell.configure(title: tab.title, isActive: isActive, isAddButton: false, isPreview: tab.isPreview)
            cell.onClose = { [weak self] in
                self?.closeTab(at: indexPath.item)
            }
        } else {
            cell.configure(title: "+", isActive: false, isAddButton: true)
            cell.onClose = nil
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.item < tabs.count {
            switchToTab(at: indexPath.item)
        } else {
            // “+”按钮：新建一个正式 Tab
            openNewTab(article: nil, isPreview: false)
        }
    }
}

// MARK: - TabBarCell
class TabBarCell: UICollectionViewCell {
    static let reuseId = "TabBarCell"

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private var stackView: UIStackView!

    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        layer.cornerRadius = 8
        layer.masksToBounds = true

        titleLabel.font = UIFont.systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.widthAnchor.constraint(equalToConstant: 24).isActive = true

        stackView = UIStackView(arrangedSubviews: [titleLabel, closeButton])
        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 120)
        ])
    }

    func configure(title: String, isActive: Bool, isAddButton: Bool, isPreview: Bool = false) {
        titleLabel.text = title
        closeButton.isHidden = isAddButton
        backgroundColor = isActive ? .systemBackground : .secondarySystemBackground
        titleLabel.textColor = isActive ? .label : .secondaryLabel
        if isAddButton {
            titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .light)
        } else {
            // 预览 Tab 用斜体 + 更浅颜色，强调“可复用”状态；
            // 正式 Tab 用正常字体，强调“已固定/不复用”。
            titleLabel.font = isPreview ? UIFont.italicSystemFont(ofSize: 13) : UIFont.systemFont(ofSize: 13)
        }
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
