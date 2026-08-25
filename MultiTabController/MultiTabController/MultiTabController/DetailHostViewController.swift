import UIKit

// MARK: - 单个详情 Tab 的数据
// 每个 tab 记录 id、对应的内容项、持有的内容页（PPContentDisplaying），
// 以及它是否为”预览 Tab”（可复用）。
// controller 是强引用——这正是多 Tab”保活”的本质：控制器不销毁，状态就还在。
private struct DetailTabItem {
    let id: String
    var item: PPContentItem?
    let controller: PPContentDisplaying
    var isPreview: Bool
}

// MARK: - DetailHostViewController
// 右侧多 Tab 详情宿主：承载 VS Code 式”复用 Tab 策略”：
//   - preview（单击）：复用已有的”预览 Tab”；没有则新建一个预览 Tab。
//   - newTab（双击 / “新Tab打开”）：永远新建正式 Tab，不复用。
//   - 内容页上报”已编辑”：把当前 Tab 固定为正式 Tab（不再被预览复用覆盖）。
// 库本身不认识 Tab 里显示什么：每个 Tab 的内容页由外部通过 PPContentViewControllerProvider 提供，
// 只要求它满足 PPContentDisplaying。多个内容页作为子控制器保活（addChild）；
// 视图层面只有当前选中 tab 的 view 挂在视图树上，切走即 removeFromSuperview、切回再 add，
// 这样 tab 再多也只有 1 个 view 参与 layout（controller 不销毁，状态保活不受影响）。
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
        // 首次进入做一次全量同步（此时必无 Tab，代价为零）；
        // 之后的增删改都走精细化的 insert/delete/reload item。
        collectionView.reloadData()
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
            let previousID = selectedTabID
            load(item: item, into: index)
            selectedTabID = tabs[index].id
            refreshUI()

            // 被复用的预览 Tab 标题变了且成为选中：精细化只刷受影响的 cell。
            var indexPaths = [IndexPath(item: index, section: 0)]
            if let previousIndex = tabBarIndexPath(ofTabID: previousID), previousIndex.item != index {
                indexPaths.append(previousIndex)
            }
            updateTabBar(reload: indexPaths, insert: [], delete: [])
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
        let previousID = selectedTabID
        selectedTabID = tabs[indexPath.item].id
        refreshUI()

        // 切 tab 只改变选中态：精细化只 reload 新旧两个 cell，不全量 reloadData。
        var indexPaths = [indexPath]
        if let previousIndex = tabBarIndexPath(ofTabID: previousID), previousIndex != indexPath {
            indexPaths.append(previousIndex)
        }
        updateTabBar(reload: indexPaths, insert: [], delete: [])
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
        // 载入新内容：协议约定 configure 内部会把编辑状态复位为未编辑，
        // 宿主复用预览 Tab 时本就是预览态，无需在这里另外复位。
        tabs[index].controller.configure(with: item)
    }

    private func appendTab(for item: PPContentItem?, isPreview: Bool) {
        // 通过外部注入的工厂创建内容页（库不认识具体内容，显示什么由集成方决定）。
        let controller = contentViewControllerProvider()
        // 注入上报通道：内容页通过它上报“编辑态变化 / 想以某种方式打开内容”。
        controller.contentHost = self
        if let item = item {
            controller.configure(with: item)
        }

        let tabID = UUID().uuidString
        // 记住原选中，追加后要取消它的选中样式。
        let previousID = selectedTabID

        // 作为子控制器保活（只 addChild，view 的挂载/拆卸由 refreshUI 统一管理）。
        addChild(controller)
        controller.didMove(toParent: self)

        tabs.append(DetailTabItem(id: tabID, item: item, controller: controller, isPreview: isPreview))
        selectedTabID = tabID
        refreshUI()

        // 精细化：插入新 cell；原选中 cell 取消选中态。
        updateTabBar(
            reload: tabBarIndexPath(ofTabID: previousID).map { [$0] } ?? [],
            insert: [IndexPath(item: tabs.count - 1, section: 0)],
            delete: []
        )
    }

    private func closeTab(withID id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let wasSelected = selectedTabID == id
        let tab = tabs.remove(at: index)
        // view 可能还挂在视图树上（它是被选中态关掉的），先拆下来再移除子控制器。
        detachContentView(of: tab.controller)
        tab.controller.willMove(toParent: nil)
        tab.controller.removeFromParent()

        if tabs.isEmpty {
            selectedTabID = nil
        } else if wasSelected {
            // 关掉的是当前 Tab，则切到相邻的那个。
            let nextIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[nextIndex].id
        }

        refreshUI()

        // 精细化：删除被关的 cell；若选中转移到了相邻 Tab，顺便刷新它的选中样式。
        updateTabBar(
            reload: wasSelected ? tabBarIndexPath(ofTabID: selectedTabID).map { [$0] } ?? [] : [],
            insert: [],
            delete: [IndexPath(item: index, section: 0)]
        )
    }

    // 把某个 Tab 设为预览/正式，并刷新对应 cell 的样式。
    private func setPreview(_ value: Bool, for controller: UIViewController) {
        guard let index = tabs.firstIndex(where: { $0.controller === controller }) else { return }
        tabs[index].isPreview = value
        collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
    }

    // MARK: - 私有：Tab 条的精细化更新

    // 按 tab id 查它在 Tab 条里的位置（不在/为 nil 时返回 nil）。
    private func tabBarIndexPath(ofTabID id: String?) -> IndexPath? {
        guard let id = id, let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        return IndexPath(item: index, section: 0)
    }

    // Tab 条更新遵循“能少刷就少刷”：切 tab / 开 / 关都不全量 reloadData，
    // 而是按需 reload / insert / delete 受影响的 item，避免全部 cell 重建与全量布局。
    // 滚动放在 performBatchUpdates 的 completion 里：此时布局已就绪，
    // 无需再 DispatchQueue.main.async 延后滚动。
    private func updateTabBar(reload: [IndexPath], insert: [IndexPath], delete: [IndexPath]) {
        collectionView.performBatchUpdates({ [weak self] in
            guard let self = self else { return }
            if !reload.isEmpty { self.collectionView.reloadItems(at: reload) }
            if !delete.isEmpty { self.collectionView.deleteItems(at: delete) }
            if !insert.isEmpty { self.collectionView.insertItems(at: insert) }
        }) { [weak self] _ in
            self?.scrollToSelectedItem(animated: true)
        }
    }

    // 把选中的 Tab 滚动到可见区域（无选中项时什么都不做）。
    private func scrollToSelectedItem(animated: Bool) {
        guard let indexPath = tabBarIndexPath(ofTabID: selectedTabID) else { return }
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
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

    // MARK: - 私有：内容视图的挂载 / 拆卸（视图层面的保活优化）

    // 保活只需保住 controller（状态），不需要 view 常驻视图树：
    // 只有当前选中 tab 的 view 挂在 contentContainerView 上，其余全部 removeFromSuperview。
    // tab 一多，参与 layout 的内容视图始终只有 1 个。
    private func mountContentView(of controller: PPContentDisplaying) {
        // 通过协议存在类型访问 UIViewController.view 得到的是可选值，先解包。
        guard let contentView = controller.view else { return }
        // 已在树上就不重复挂（如连续 refreshUI），避免重复加约束。
        guard contentView.superview !== contentContainerView else { return }
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor)
        ])
        // view 是手动拆装而非系统容器切换，UIKit 不会自动重发 appearance 回调，
        // 这里补上，让内容页的 viewWillAppear/viewDidAppear 时机与语义对齐。
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
    }

    // 切走/关闭时把 view 从视图树上拆下来：子控制器关系（addChild）不动，状态照旧保活；
    // view 的约束随 removeFromSuperview 自动失效，下次挂载时重建。
    private func detachContentView(of controller: PPContentDisplaying) {
        guard let contentView = controller.view else { return }
        guard contentView.superview === contentContainerView else { return }
        // 对称地补上“即将消失”的 appearance 回调。
        controller.beginAppearanceTransition(false, animated: false)
        contentView.removeFromSuperview()
        controller.endAppearanceTransition()
    }

    // 只负责“壳”与内容视图：占位/分隔线/高度的显隐，以及内容视图的挂载/拆卸。
    // Tab 条（collectionView）的数据更新不在这里做，由各调用点按需精细化处理。
    private func refreshUI() {
        let hasTabs = !tabs.isEmpty
        collectionView.isHidden = !hasTabs
        separatorView.isHidden = !hasTabs
        placeholderLabel.isHidden = hasTabs
        collectionViewHeightConstraint?.constant = hasTabs ? 44 : 0
        separatorHeightConstraint?.constant = hasTabs ? 1 : 0

        // 只挂载选中 tab 的 view，其余全部拆下（替代旧实现“全部挂树 + isHidden”）。
        for tab in tabs {
            if tab.id == selectedTabID {
                mountContentView(of: tab.controller)
            } else {
                detachContentView(of: tab.controller)
            }
        }
    }
}

// MARK: - PPContentHosting（内容页 -> 宿主的上报通道）
// 内容页通过宿主注入的 contentHost 上报意图，宿主在这里统一决策，
// 替代旧实现里每个 Tab 各自绑三个闭包的做法。
extension DetailHostViewController: PPContentHosting {

    // 内容页上报“编辑态变化”：编辑过的内容页把所在 Tab 固定为正式 Tab（不再被预览复用覆盖）。
    public func contentViewController(_ contentViewController: UIViewController,
                                      didChangeEditedState isEdited: Bool) {
        setPreview(!isEdited, for: contentViewController)
    }

    // 内容页请求以指定方式打开一个内容项（详情页里的“在新 Tab / 新窗口打开”入口）。
    public func contentViewController(_ contentViewController: UIViewController,
                                      requestsOpen item: PPContentItem,
                                      mode: PPContentOpenMode) {
        // 复用统一的 mode 分发：.newWindow 由 open(_:mode:) 兜底交给 WindowManager。
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
