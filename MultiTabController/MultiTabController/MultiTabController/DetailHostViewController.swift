import UIKit

// MARK: - 单个详情 Tab 的数据
// 每个 tab 记录 id、对应的内容项、持有的内容页（PPContentDisplaying），
// 以及它是否为“预览 Tab”（可复用）。
// controller 是强引用——这正是多 Tab“保活”的本质：控制器不销毁，状态就还在。
private struct DetailTabItem {
    let id: String
    var item: PPContentItem?
    let controller: PPContentDisplaying
    var isPreview: Bool
}

// MARK: - DetailHostViewController
// 右侧多 Tab 详情宿主：承载 VS Code 式“复用 Tab 策略”：
//   - preview（单击）：复用已有的“预览 Tab”；没有则新建一个预览 Tab。
//   - newTab（双击 / “新Tab打开”）：永远新建正式 Tab，不复用。
//   - 内容页上报“已编辑”：把当前 Tab 固定为正式 Tab（不再被预览复用覆盖）。
// 库本身不认识 Tab 里显示什么：每个 Tab 的内容页由外部通过 PPContentViewControllerProvider 提供，
// 只要求它满足 PPContentDisplaying。多个内容页作为子控制器保活（addChild），切换时只隐藏/显示。
public final class DetailHostViewController: UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout {

    // 内容页工厂：每新建一个 Tab 就调用一次，返回一个全新的内容页实例。由外部注入（必填）。
    private let contentViewControllerProvider: PPContentViewControllerProvider

    // 内容容器：当前激活的内容页显示在这里。
    private let contentContainerView = UIView()
    // 没有 Tab 时显示的占位文案。
    private let placeholderLabel = UILabel()
    // Tab 条与内容之间的分隔线。
    private let separatorView = UIView()

    // 左栏展开/折叠按钮：放在 Tab 条（collectionView）的最左侧。
    // 点击后不自己处理，而是通过 onToggleSidebarRequest 回调通知父容器（SplitContainerViewController），
    // 由父容器真正执行 leftContainerView 的展开/折叠（模仿 UISplitViewController 的 showColumn/hideColumn）。
    private let sidebarToggleButton = UIButton(type: .system)

    // 当前左栏是否处于折叠状态（决定按钮图标：折叠时显示“向右箭头”，提示点击可展开）。
    private var isSidebarCollapsed = false

    /// 点击侧栏按钮时的回调：由父容器（SplitContainerViewController）执行左栏的展开/折叠。
    public var onToggleSidebarRequest: (() -> Void)?

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

    /// 用内容页工厂初始化。
    /// - Parameter contentViewControllerProvider: 每新建一个 Tab 调用一次，返回一个全新的内容页。
    ///   本库不含任何内容 UI，Tab 里显示什么完全由这个工厂决定。
    public init(contentViewControllerProvider: @escaping PPContentViewControllerProvider) {
        self.contentViewControllerProvider = contentViewControllerProvider
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // public 类里 override 系统 open 方法必须同样声明 public（编译器强制要求）
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupViews()
        refreshUI()
    }

    // MARK: - 侧栏按钮状态（由父容器在展开/折叠后调用，保持图标与状态一致）

    /// 父容器展开/折叠左栏后调用，用来同步按钮图标。
    public func setSidebarCollapsed(_ collapsed: Bool) {
        isSidebarCollapsed = collapsed
        updateSidebarButtonIcon()
    }

    // 点击侧栏按钮：自己不执行任何布局变化，只把“想展开/折叠”的意图通知父容器。
    @objc private func sidebarButtonTapped() {
        onToggleSidebarRequest?()
    }

    // 折叠状态显示“向右箭头”（提示点击可展开左栏），展开状态显示 sidebar 图标（提示点击可收起）。
    private func updateSidebarButtonIcon() {
        if #available(iOS 13.0, *) {
            let symbolName = "sidebar.leading"
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            sidebarToggleButton.setImage(UIImage(systemName: symbolName, withConfiguration: config), for: .normal)
        } else {
            sidebarToggleButton.setTitle("☰", for: .normal)
        }
    }

    // MARK: - 对外的“打开文章”入口（由 router 调用）

    /// 预览（单击）：复用已有的预览 Tab；没有则新建一个预览 Tab。
    public func openPreview(_ item: PPContentItem) {
        if let index = tabs.firstIndex(where: { $0.isPreview }) {
            // 复用预览槽位：把内容加载进去并切过去。
            load(item: item, into: index)
            selectedTabID = tabs[index].id
            refreshUI()
        } else {
            // 没有预览 Tab（当前都是正式 Tab）-> 新建一个预览 Tab。
            appendTab(for: item, isPreview: true)
        }
    }

    /// 正式 Tab（双击 / 在详情里点“新Tab打开”）：永远新建，不复用。
    public func openNewTab(_ item: PPContentItem? = nil) {
        appendTab(for: item, isPreview: false)
    }

    /// 兼容 NewsSplitDemo 式 mode 分发（router 直接调这个即可）。
    public func open(_ item: PPContentItem, mode: PPContentOpenMode) {
        switch mode {
        case .preview:
            openPreview(item)
        case .newTab:
            openNewTab(item)
        case .newWindow:
            // 新窗口由 router 层决定，这里兜底也处理一下。
            WindowManager.openNewWindow(item: item)
        }
    }

    // MARK: - UICollectionView 数据源 / 代理

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        tabs.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: DetailTabCell.reuseIdentifier,
            for: indexPath
        ) as? DetailTabCell else {
            return UICollectionViewCell()
        }

        let tab = tabs[indexPath.item]
        cell.configure(
            title: tab.item?.title ?? "New Tab",
            selected: tab.id == selectedTabID,
            isPreview: tab.isPreview
        )
        cell.onClose = { [weak self] in
            self?.closeTab(withID: tab.id)
        }
        return cell
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedTabID = tabs[indexPath.item].id
        refreshUI()
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let title = (tabs[indexPath.item].item?.title ?? "New Tab") as NSString
        let width = title.size(withAttributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
        ]).width
        return CGSize(width: min(max(width + 46, 120), 240), height: 34)
    }

    // MARK: - 私有：Tab 管理

    private func load(item: PPContentItem, into index: Int) {
        tabs[index].item = item
        // 载入新内容：configure 内部负责渲染并复位内容页自身的编辑态。
        tabs[index].controller.configure(with: item)
    }

    private func appendTab(for item: PPContentItem?, isPreview: Bool) {
        let controller = contentViewControllerProvider()
        // 先注入宿主通道，再 configure：这样内容页在 configure 时就能依据“有无宿主”决定 UI
        // （例如无宿主时隐藏“新 Tab / 新窗口”入口）。内容页应以 weak 持有它，避免循环引用。
        controller.contentHost = self
        if let item = item {
            controller.configure(with: item)
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

        tabs.append(DetailTabItem(id: tabID, item: item, controller: controller, isPreview: isPreview))
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
    // 用 UIViewController 作参数：PPContentDisplaying 是 class-bound 协议，=== 恒等比较照常可用。
    private func setPreview(_ value: Bool, for controller: UIViewController) {
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
        placeholderLabel.textColor = .pp_tertiaryLabel

        // 侧栏展开/折叠按钮：与 Tab 条等高、位于其最左侧。
        sidebarToggleButton.translatesAutoresizingMaskIntoConstraints = false
        sidebarToggleButton.tintColor = UIColor(white: 0.35, alpha: 1.0)
        sidebarToggleButton.addTarget(self, action: #selector(sidebarButtonTapped), for: .touchUpInside)
        updateSidebarButtonIcon()

        view.addSubview(collectionView)
        view.addSubview(separatorView)
        view.addSubview(contentContainerView)
        view.addSubview(sidebarToggleButton)
        contentContainerView.addSubview(placeholderLabel)

        let collectionViewHeightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 44)
        let separatorHeightConstraint = separatorView.heightAnchor.constraint(equalToConstant: 1)
        self.collectionViewHeightConstraint = collectionViewHeightConstraint
        self.separatorHeightConstraint = separatorHeightConstraint

        NSLayoutConstraint.activate([
            // 侧栏按钮：贴在左侧，与 Tab 条同一行、同一高度（即使没有 Tab 时也保持可见，方便随时展开左栏）。
            sidebarToggleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            sidebarToggleButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            sidebarToggleButton.widthAnchor.constraint(equalToConstant: 32),
            sidebarToggleButton.heightAnchor.constraint(equalToConstant: 44),

            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            // Tab 条从侧栏按钮的右边开始排布。
            collectionView.leadingAnchor.constraint(equalTo: sidebarToggleButton.trailingAnchor, constant: 8),
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

// MARK: - PPContentHosting
// 接收内容页上报的意图，翻译成本宿主的 Tab 操作。
extension DetailHostViewController: PPContentHosting {

    // 内容页编辑态变化：已编辑 -> 把承载它的 Tab 固定为正式 Tab（isPreview = false）。
    public func contentViewController(_ contentViewController: UIViewController,
                                      didChangeEditedState isEdited: Bool) {
        setPreview(!isEdited, for: contentViewController)
    }

    // 内容页请求打开一个内容项：直接复用本宿主既有的 mode 分发（含 .newWindow 的兜底）。
    public func contentViewController(_ contentViewController: UIViewController,
                                      requestsOpen item: PPContentItem,
                                      mode: PPContentOpenMode) {
        open(item, mode: mode)
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
