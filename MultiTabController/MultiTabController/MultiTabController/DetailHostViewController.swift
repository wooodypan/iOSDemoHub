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

// MARK: - Tab 条的尺寸常量
// Tab 条（collectionView）整体 44pt 高；Tab 单元格顶部留 5pt 呼吸位、底边与 Tab 条底边对齐，
// 于是单元格高度 = 44 - 5 = 39。
// 这几个数字同时被「约束 / 刷新 / sizeForItemAt / 单元格圆角」用到，收在一处，
// 以后想调高矮或间距只改这里，不用满文件找魔法数。
private enum DetailTabBarMetrics {
    // Tab 条整体高度（有 Tab 时）；没有 Tab 时会被压成 0，整条收起来。
    static let barHeight: CGFloat = 36
    // Tab 单元格顶部与 Tab 条顶部的间距（底部为 0，单元格贴着 Tab 条下边缘）。
    static let cellTopSpacing: CGFloat = 1
    // Tab 条左右两端的内边距。
    static let horizontalPadding: CGFloat = 1
    // 单元格高度：高度全给上面留出的间距，剩下的贴到底。
    static let cellHeight: CGFloat = barHeight - cellTopSpacing
    // 单元格圆角半径（只圆上面两个角，像浏览器标签页那样“从底边长出来”）。
    static let cellCornerRadius: CGFloat = 8
}

// MARK: - DetailHostViewControllerDelegate
// 选中 Tab 变化时的通知协议。
// 库不关心左侧列表长什么样，只负责在“当前选中的内容变了”时告诉集成方；
// 集成方可以据此同步左侧列表的高亮（模仿 VS Code 资源管理器：右侧切哪个文件，左侧就高亮哪一行）。
public protocol DetailHostViewControllerDelegate: AnyObject {
    /// 右侧选中的 Tab 发生变化（点 Tab、打开 / 复用内容、关闭 Tab 后自动切换都会触发）。
    /// - Parameter item: 新选中 Tab 对应的内容；`nil` 表示当前没有选中任何内容
    ///   （例如所有 Tab 都已关闭，或选中的是一个没有内容的空 Tab）。
    func detailHost(_ host: DetailHostViewController, didSelectItem item: PPContentItem?)
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

    // MARK: 选中项变化通知（供左侧列表同步高亮）

    /// 选中项变化代理。与 `onSelectedItemChanged` 二选一即可，两者都会触发。
    /// - Note: 赋值时会立即按当前选中项回调一次，方便晚接入的集成方补上初始高亮。
    public weak var delegate: DetailHostViewControllerDelegate? {
        didSet { sendCurrentSelectionToListeners() }
    }

    /// 选中项变化回调（闭包版）。`nil` 表示当前没有选中任何内容。
    /// 适合“只有一个同步逻辑”的简单接入；需要多处监听时用 delegate。
    /// - Note: 赋值时会立即按当前选中项回调一次；本属性会被宿主强持有，
    ///   闭包里请用 `weak` 捕获外部对象，避免循环引用。
    public var onSelectedItemChanged: ((PPContentItem?) -> Void)? {
        didSet { sendCurrentSelectionToListeners() }
    }

    /// 当前选中 Tab 对应的内容；没有选中 Tab、或选中的是空 Tab 时为 `nil`。
    public var selectedItem: PPContentItem? {
        guard let id = selectedTabID else { return nil }
        return tabs.first(where: { $0.id == id })?.item
    }

    // 通知去重：关闭“未选中的 Tab”等场景选中项并没有变，没必要让左侧列表重复刷新。
    private var hasNotifiedSelection = false
    private var lastNotifiedItemID: String?

    // 统一的通知出口：选中项真的变了才回调。
    // 注意按“内容 id”而不是 tab id 判断：预览 Tab 被复用时 tab id 不变，但内容换了，
    // 左侧高亮也必须跟着换。
    private func notifySelectionChanged() {
        let item = selectedItem
        if hasNotifiedSelection, lastNotifiedItemID == item?.id { return }
        hasNotifiedSelection = true
        lastNotifiedItemID = item?.id
        delegate?.detailHost(self, didSelectItem: item)
        onSelectedItemChanged?(item)
    }

    // 新监听方接入时（赋值 delegate / 闭包）立刻把当前状态同步给它，
    // 这样即使 Tab 早已打开、监听是后来才接上的，左侧也能拿到正确的初始高亮。
    private func sendCurrentSelectionToListeners() {
        let item = selectedItem
        hasNotifiedSelection = true
        lastNotifiedItemID = item?.id
        delegate?.detailHost(self, didSelectItem: item)
        onSelectedItemChanged?(item)
    }

    /// 是否按内容 ID（`PPContentItem.id`）去重。默认 **true**。
    ///
    /// - `true`：打开一个**已经打开过**的内容时，不再新建 Tab，而是直接定位（切换）到那个 Tab。
    ///   例如先后双击打开 Article 1、Article 2，再单击 Article 1 ——
    ///   会直接切回 Article 1 那个 Tab，而不是开出第三个标签。
    /// - `false`：保留原来的 VS Code 语义（预览槽位复用 / 双击永远新建），
    ///   同一个内容允许被开成多个 Tab。
    ///
    /// 去重只按 `PPContentItem.id` 比较，所以请保证你的业务 id 在同一个宿主里唯一。
    public var deduplicateOpenedItems: Bool = true

    // MARK: 冷启动恢复（单宿主覆盖）
    //
    // 下面三个属性默认都是 nil，意思是「不表态，跟随全局 PPTabRestoration」。
    // 只有想让某个宿主单独开 / 单独关 / 单独用一份存档时才需要设置。
    //
    // 它们都只在宿主 view 第一次加载（viewDidLoad）时被读一次：
    //   - 在这之前设置（init 之后、上屏之前）立即生效；
    //   - 在这之后设置不会补做恢复，也不会改变保存用的键，
    //     避免出现「恢复读 A 键、保存写 B 键」这种错位。

    /// 本宿主是否在首次加载时恢复上次的 Tab。
    /// - `nil`（默认）：跟随全局 `PPTabRestoration.isEnabled`
    /// - `true` / `false`：只对当前宿主生效，覆盖全局
    ///
    /// 典型用法是辅助窗口不恢复：主窗口跟着全局走，次要窗口设成 `false`。
    public var restoresTabsOnLaunch: Bool?

    /// 本宿主专用的存档键。`nil`（默认）= 用全局 `PPTabRestoration.persistenceKey`。
    ///
    /// 多窗口 / 多个宿主同时存在时必须分开，否则两边会互相覆盖对方的快照。
    /// 注意这里**不能**在 viewDidLoad 时自动按窗口 / 场景拼一个后缀：那一刻宿主还没进窗口，
    /// `view.window` 是 nil。需要按场景区分的，请在 SceneDelegate 里拿到
    /// `session.persistentIdentifier` 后，通过工厂闭包把键传进来。
    public var tabRestorationKey: String?

    /// 本宿主专用的内容解析器。`nil`（默认）= 用全局 `PPTabRestoration.contentResolver`。
    ///
    /// 给「一个 App 里有多套数据源 / 多个模块各自管理内容」的场景用；单数据源留 nil 即可。
    /// 宿主会强持有这个闭包，捕获外部对象请用 weak。
    public var tabRestorationResolver: ((String) -> PPContentItem?)?

    /// 选中 Tab 的底色（作用在单元格的 `contentView.backgroundColor` 上）。
    /// 默认值 `UIColor.pp_tabSelectedBackground` 是动态色：浅色下浅灰、深色下深灰，跟随系统外观自动变。
    ///
    /// 想跟自己的主题走，直接赋值即可：
    /// ```swift
    /// host.tabSelectedBackgroundColor = .white
    /// host.tabUnselectedBackgroundColor = UIColor(white: 0.85, alpha: 1.0)
    /// ```
    /// 赋值后已经在屏幕上的 Tab 会立刻改色（只重刷单元格，不重建整条 Tab 条）。
    /// 想自定义成「浅色/深色各一份」的颜色，可以用 `UIColor.pp_adaptive(light:dark:)` 造一个。
    public var tabSelectedBackgroundColor: UIColor = .pp_tabSelectedBackground {
        didSet {
            applyTabBarColors()
        }
    }

    /// 未选中 Tab 的底色。默认 `.clear` —— 也就是不涂色，
    /// 直接露出 Tab 条（collectionView）自身的背景色。赋值后的行为同上。
    public var tabUnselectedBackgroundColor: UIColor = .clear {
        didSet {
            applyTabBarColors()
        }
    }

    // Mac Catalyst 专用：⌘W 在 Catalyst 下走 AppKit 的按键等价派发（NSWindow 的 performClose:），
    // UIKeyCommand 抢不过它，所以要额外装一个底层键盘监听兜底（见 CatalystKeyInterceptor）。
    // 必须强持有：这个实例被释放时监听会自动移除。
    #if targetEnvironment(macCatalyst)
    private var catalystKeyInterceptor: CatalystKeyInterceptor?
    #endif


    

    private lazy var collectionViewLayout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = 8
        // 间距统一交给 sectionInset：顶部 5pt 留白、底部 0（单元格贴着 Tab 条下边缘）。
        // 单元格高度 = 44 - 5，与这里的 top 5 + bottom 0 正好把 Tab 条填满，
        // 所以不管 flow layout 在交叉轴上怎么对齐，单元格都只会落在「上留 5pt、下贴边」。
        layout.sectionInset = UIEdgeInsets(
            top: DetailTabBarMetrics.cellTopSpacing,
            left: DetailTabBarMetrics.horizontalPadding,
            bottom: 0,
            right: DetailTabBarMetrics.horizontalPadding
        )
        return layout
    }()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        // 标签条自身不涂色（完全透明），露出后面的容器背景；容器背景是语义色，深色下会跟着变黑。
        collectionView.backgroundColor = .clear
        // 关掉系统按安全区自动追加的 inset：Tab 条的上下间距我们自己用 sectionInset 算好了，
        // 让系统再加一份会算不准（Tab 条本身就约束在安全区下方，并不需要系统补偿）。
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.layer.cornerRadius = DetailTabBarMetrics.cellCornerRadius
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(DetailTabCell.self, forCellWithReuseIdentifier: DetailTabCell.reuseIdentifier)
        return collectionView
    }()

    // 所有 Tab（强引用子控制器即实现“保活”）。
    private var tabs: [DetailTabItem] = []
    private var selectedTabID: String?

    // MARK: 冷启动恢复的内部状态（具体实现见文件后面的「私有：冷启动恢复」）

    // 全局配置与本宿主覆盖项合并后的结果。nil = 本宿主既不恢复也不保存。
    private var restorationConfig: ResolvedTabRestoration?
    // 是否已经尝试过恢复。视图加载时无论开关开着还是关着都会置位：
    // 这样之后再把全局开关打开，也不会突然往这个已经上屏的宿主里塞 Tab。
    private var didAttemptTabRestoration = false
    // 恢复过程中禁止写盘（原因见 restoreTabsIfNeeded 里的注释）。
    private var isRestoringTabs = false
    // 恢复后需要滚动一次到选中的 Tab；viewDidLoad 时宽度可能还是 0，所以推迟到布局完成再做。
    private var needsScrollToRestoredSelection = false

    // 一次求值的结果：键和解析器绑在一起存，保证「从哪把键读的，就写回哪把键」。
    private struct ResolvedTabRestoration {
        let persistenceKey: String
        let contentResolver: (String) -> PPContentItem?
    }

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
        view.backgroundColor = .clear
        setupViews()
        refreshUI()
        // 冷启动恢复：必须在这里，而且必须早于下面的 reloadData。
        // 恢复是「一次性把 tabs 数组填好」，让本次 reloadData 把恢复结果当成集合视图的基线；
        // 放到 reloadData 之后再恢复，就只能补一次批量 insert，正好撞上 appendTab 注释里写的那个异常。
        restoreTabsIfNeeded()
        // Mac Catalyst 下装底层键盘监听，用来真正拦下 ⌘W（详见方法内注释）。
        installCatalystKeyInterceptorIfNeeded()
        // 首次进入做一次全量同步；恢复出来的 Tab 会作为这次 reloadData 的基线。
        // 之后的增删改都走精细化的 insert/delete/reload item。
        collectionView.reloadData()
    }

    // MARK: - 键盘快捷键（Command + W 关闭当前 Tab）
    /// 是否在关闭最后一个 Tab 后弹出“是否退出 App”确认框。默认 false。
    /// 集成方可以用这个开关关闭退出确认弹框（例如不希望用户直接退出应用）。
    public var showExitPromptWhenAllTabsClosed: Bool = false

    /// 自定义的“退出 App”动作。默认 nil 时走平台默认实现：
    ///   - Mac Catalyst：调用系统退出（NSApplication.terminate，等价于 Cmd+Q）
    ///   - 其它平台（iOS/iPadOS）：iOS 没有官方“退出 App”API（App Store 审核也会拒绝 exit()），
    ///     演示场景用 exit(0) 兜底；生产环境请注入自己的实现（例如“回到首页”）。
    public var exitAction: (() -> Void)?

    // UIViewController 默认不能成为 first responder；硬件键盘的 keyCommands
    // 需要响应链上有人返回快捷键列表，所以这里允许成为 first responder。
    public override var canBecomeFirstResponder: Bool { true }

    // 视图出现后申请成为 first responder，保证硬件键盘按键能送达本控制器。
    // （iPad 配键盘、Mac Catalyst 都走这套机制。）
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    // 恢复出来的 Tab 要滚到可见区域，但 viewDidLoad 时 bounds 往往还是 0，
    // 那一刻 scrollToItem 会算出错误的偏移。等这里拿到真实宽度后再滚，只做一次、不带动画。
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard needsScrollToRestoredSelection, view.bounds.width > 0 else { return }
        needsScrollToRestoredSelection = false
        scrollToSelectedItem(animated: false)
    }

    // 向系统声明本控制器支持的键盘快捷键列表。
    // 硬件键盘按键时，系统会沿响应链询问各对象的 keyCommands 并做匹配。
    public override var keyCommands: [UIKeyCommand]? {
        // Command + W：关闭当前选中的 Tab（模仿桌面浏览器的“关闭标签页”快捷键）。
        // 注意：用 input 版本的老初始化器（iOS 7+），
        // 带 title 的版本在 iOS 12 deployment target 下会解析到 iOS 13+ 的重载，编译报错。
        let closeTabCommand = UIKeyCommand(
            input: "w",
            modifierFlags: .command,
            action: #selector(handleCloseCurrentTab(_:))
        )
        // title：Mac Catalyst 菜单栏 / iPad 长按 Command 的快捷键面板里显示的名字。
        // 注意：UIKeyCommand.title 属性在 Xcode 26 SDK 里标注为 iOS 13+（iOS 12 没有 Catalyst，
        // 无实际影响），所以用 #available 保护以兼容 iOS 12 deployment target。
        if #available(iOS 13.0, *) {
            closeTabCommand.title = "关闭当前标签页Z"
        }
        // discoverabilityTitle：快捷键面板里的说明文字（iOS 7+，无版本问题）。
        closeTabCommand.discoverabilityTitle = "关闭当前标签页Z"
        return [closeTabCommand]
    }

    // Command + W 的响应（UIKeyCommand 路径：iPad 外接键盘等场景）：关闭当前选中的 Tab。
    @objc private func handleCloseCurrentTab(_ sender: UIKeyCommand) {
        closeCurrentTab()
    }

    // 统一的“关闭当前选中 Tab”入口：快捷键、Catalyst 底层监听最终都走这里。
    private func closeCurrentTab() {
        // 没有选中任何 Tab（例如所有 Tab 已关闭、处于空状态）就什么都不做。
        guard let selectedID = selectedTabID else { return }
        closeTab(withID: selectedID)
    }

    // MARK: - Mac Catalyst 兜底：在 AppKit 处理 ⌘W 之前把它拦下来

    // ⌘W 在 Catalyst 下是系统菜单 “Close Window” 的按键等价（key equivalent），
    // 由 AppKit 在 NSWindow 上执行 performClose:，优先级高于 UIKeyCommand。
    // 所以光靠上面的 keyCommands / buildMenu / canPerformAction 拦不住，
    // 这里装一个 NSEvent 本地事件监听——它运行在“按键等价处理之前”，
    // 这是苹果在 WWDC《Key Event Handling in Cocoa Applications》里给出的标准做法。
    private func installCatalystKeyInterceptorIfNeeded() {
        #if targetEnvironment(macCatalyst)
        catalystKeyInterceptor = CatalystKeyInterceptor { [weak self] event in
            guard let self = self else { return false }
            return self.handleCatalystKeyEvent(event)
        }
        #endif
    }

    // 处理 Catalyst 下拦截到的按键事件。
    // 返回 true = 这个按键已被处理，事件要被吞掉（AppKit 不会再执行 ⌘W 关闭窗口）；
    // 返回 false = 不处理，放行给系统走默认行为。
    #if targetEnvironment(macCatalyst)
    private func handleCatalystKeyEvent(_ event: AnyObject) -> Bool {
        // 只关心 Command + W。
        guard CatalystKeyInterceptor.isCommandPressed(with: "w", in: event) else { return false }

        // 正在显示“是否退出 App”确认框时，⌘W 什么也不做，避免绕过确认直接退出。
        if topMostPresentedViewController() is UIAlertController { return true }

        // 多窗口场景：只有自己的窗口是当前活动窗口时才响应，
        // 否则第二个窗口里的宿主也会跟着关 Tab。
        guard view.window?.isKeyWindow == true else { return false }

        // 一个 Tab 都没有：放行，让系统按默认行为处理（关窗口 / 退出 App）。
        guard selectedTabID != nil else { return false }

        // 关掉当前选中的 Tab（与点关闭按钮、iPad 快捷键走完全相同的逻辑）。
        closeCurrentTab()
        // 吞掉事件：不让 AppKit 再执行 ⌘W 的“关闭窗口”。
        return true
    }
    #endif

    // 补充说明：下面两个方法是 UIKit 层的“双保险”，在 iPadOS 菜单 / 部分场景下仍有用，
    // 但 Catalyst 下真正起作用的是上面的本地事件监听。

    // 关键点 1：Mac Catalyst / iPadOS 下，⌘W 默认被系统菜单里的 "Close Window"（performClose:）
    // 抢占——它是系统级菜单命令，走菜单命令派发，优先级高于普通 UIKeyCommand，
    // 所以必须先在这里把系统菜单项移除，⌘W 才会落到我们的 keyCommands。
    // 本方法在响应链上的对象构建系统主菜单时被调用（当前宿主是右侧活跃 VC，会在链上）。
    // 注意：若你的 App 有多个窗口 / 用了 SceneDelegate，建议在 AppDelegate 或 SceneDelegate
    // 里也重写一次（主菜单是全局单例），内容同样是 builder.remove(menu: .close)。
    @available(iOS 13.0, *)
    public override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        // 只处理主菜单（Catalyst 的文件菜单 / iPadOS 的菜单），不碰右键等上下文菜单。
        guard builder.system == .main else { return }
        // 移除系统默认的 "Close Window" 命令（快捷键 ⌘W），让位给我们的自定义处理。
        builder.remove(menu: .close)
    }

    // 关键点 2：双保险——即使菜单项已被移除，系统仍可能通过响应链兜底执行
    // performClose:（例如用户重新绑定快捷键或系统菜单重建）。
    // 这里显式对 performClose: 返回 false，彻底阻止"关闭窗口"行为抢占 ⌘W。
    // 只对 Mac Catalyst 生效；iOS/iPadOS 响应链上没有这个 AppKit selector，保持默认即可。
    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        #if targetEnvironment(macCatalyst)
        if action == Selector(("performClose:")) {
            return false
        }
        #endif
        return super.canPerformAction(action, withSender: sender)
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

    /// 预览（单击）：优先复用已有的预览 Tab；没有则新建一个预览 Tab。
    /// 开启 `deduplicateOpenedItems` 后，若这个内容已经打开过，会直接切到那个 Tab 而不新建。
    public func openPreview(_ item: PPContentItem) {
        // 去重：这个内容已经在某个 Tab 里了 -> 直接定位过去，不新建。
        if deduplicateOpenedItems, let index = existingTabIndex(forItemID: item.id) {
            selectTab(at: index)
            return
        }
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

            // 预览槽位里的内容换了：通知外部同步左侧高亮。
            notifySelectionChanged()
            // 预览 Tab 的 tab id 没变，但内容和选中项变了，快照要跟着更新。
            persistTabsIfNeeded()
        } else {
            // 没有预览 Tab（当前都是正式 Tab）-> 新建一个预览 Tab。
            appendTab(for: item, isPreview: true)
        }
    }

    /// 正式 Tab（双击 / 在详情里点“新Tab打开”）：默认永远新建，不复用。
    /// 开启 `deduplicateOpenedItems` 后，若这个内容已经打开过，会直接切到那个 Tab 而不新建。
    public func openNewTab(_ item: PPContentItem? = nil) {
        // 去重：传了内容且它已经打开过 -> 直接定位过去，不新建。
        if let item = item, deduplicateOpenedItems, let index = existingTabIndex(forItemID: item.id) {
            selectTab(at: index)
            return
        }
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
            isPreview: tab.isPreview,
            selectedBackgroundColor: tabSelectedBackgroundColor,
            unselectedBackgroundColor: tabUnselectedBackgroundColor
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

        // 用户点了另一个 Tab：通知外部同步左侧高亮。
        notifySelectionChanged()
        // 选中项变了，记住它，下次启动才能停在同一页。
        persistTabsIfNeeded()
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
        // 高度取「Tab 条高度 - 顶部间距」：配合 layout 的 sectionInset（上 5 / 下 0）实现
        // 底部与 Tab 条底边对齐、顶部留 5pt。
        return CGSize(width: min(max(width + 46, 120), 240), height: DetailTabBarMetrics.cellHeight)
    }

    // MARK: - 私有：Tab 管理

    // 按内容 ID 找到“已经打开的”那个 Tab 的位置；没找到返回 nil。
    // 只比较 PPContentItem.id —— 没有内容的空 Tab（item 为 nil）不参与去重。
    private func existingTabIndex(forItemID itemID: String) -> Int? {
        return tabs.firstIndex(where: { $0.item?.id == itemID })
    }

    // 把某个位置的 Tab 设为选中：挂上它的内容视图，并只刷新受影响的两个 cell。
    // 去重命中时用它“定位”到已存在的 Tab，而不是新建。
    private func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let previousID = selectedTabID
        let newID = tabs[index].id

        // 已经是当前选中的 Tab：只把它滚动到可见区域即可，不用刷新。
        guard newID != previousID else {
            scrollToSelectedItem(animated: true)
            return
        }

        selectedTabID = newID
        refreshUI()

        // 切 tab 只改变选中态：精细化只 reload 新旧两个 cell，不全量 reloadData。
        var indexPaths = [IndexPath(item: index, section: 0)]
        if let previousIndex = tabBarIndexPath(ofTabID: previousID), previousIndex.item != index {
            indexPaths.append(previousIndex)
        }
        updateTabBar(reload: indexPaths, insert: [], delete: [])

        // 去重命中、程序化切到某个已有 Tab：通知外部同步左侧高亮。
        notifySelectionChanged()
        // 选中项变了，同步一次快照。
        persistTabsIfNeeded()
    }

    private func load(item: PPContentItem, into index: Int) {
        tabs[index].item = item
        // 载入新内容：协议约定 configure 内部会把编辑状态复位为未编辑，
        // 宿主复用预览 Tab 时本就是预览态，无需在这里另外复位。
        tabs[index].controller.configure(with: item)
    }

    // MARK: - 私有：冷启动恢复
    //
    // 恢复的唯一正确姿势是「一次性构造完整的 tabs 数组」，而不是循环调用 appendTab：
    //   - appendTab 每次都会 refreshUI + performBatchUpdates，N 个 Tab 就是 N 次布局和 N 次插入；
    //   - 视图还没加载时 append 还会撞上 appendTab 开头注释里说的基线冲突。
    // 所以这里直接把数组建好，最后交给 viewDidLoad 那一次 reloadData 统一刷新。

    // 把「全局开关」和「本宿主的三个覆盖项」合并成一份配置，只在 viewDidLoad 求值一次。
    //
    // 为什么不在 init 或属性的 didSet 里求值？
    //   init 时集成方还没拿到宿主，覆盖项一定都还是 nil；
    //   didSet 会在「先设 key、再设 resolver、最后设开关」的中间态里求值，把半配置状态固化下来。
    // 放在 viewDidLoad 一次性求值，拿到的是一份完整、稳定、可缓存的配置，恢复和保存共用同一份。
    private func resolveTabRestorationConfig() -> ResolvedTabRestoration? {
        // 三态合并：宿主说过就听宿主的，没表态才看全局。
        let enabled = restoresTabsOnLaunch ?? PPTabRestoration.isEnabled
        guard enabled else { return nil }

        // 没有解析器就还原不出内容，直接按「没开启」处理。
        // 这样连 UserDefaults 都不会读，符合「默认关闭时零副作用」的约定。
        guard let resolver = tabRestorationResolver ?? PPTabRestoration.contentResolver else {
            return nil
        }

        let key = tabRestorationKey ?? PPTabRestoration.persistenceKey
        // 空键按未配置处理，避免所有宿主挤到同一个空键上互相覆盖。
        guard !key.isEmpty else { return nil }

        return ResolvedTabRestoration(persistenceKey: key, contentResolver: resolver)
    }

    private func restoreTabsIfNeeded() {
        // viewDidLoad 只会走一次；这个标记是给「以后有人把调用挪到别处」留的保险。
        guard !didAttemptTabRestoration else { return }
        // 无论开关开着还是关着都置位：之后再把全局开关打开，也不会追溯这个宿主。
        didAttemptTabRestoration = true

        // 求值一次并缓存：保存侧也用这一份，保证读写用的是同一把键。
        restorationConfig = resolveTabRestorationConfig()
        guard let config = restorationConfig else { return }

        // 视图加载前就已经有 Tab（正常路径不会发生）：以现场为准，不混入历史。
        guard tabs.isEmpty else { return }

        // 没存过 / 脏数据 / 版本不符都返回 nil：静默当作没有历史。
        guard let snapshot = PPTabRestoration.loadSnapshot(forKey: config.persistenceKey),
              !snapshot.tabs.isEmpty else { return }

        // 恢复期间禁止写盘：此刻 tabs 还没替换完，写盘会把旧存档覆盖成空 / 半成品。
        // （内容页的 configure 里如果上报了编辑态，会走 setPreview -> persistTabsIfNeeded。）
        isRestoringTabs = true
        defer { isRestoringTabs = false }

        var restoredTabs: [DetailTabItem] = []
        var restoredSelectedIndex: Int?
        var didUsePreviewSlot = false
        let limit = min(snapshot.tabs.count, PPTabRestoration.maxRestoredTabCount)

        for savedIndex in 0..<limit {
            let saved = snapshot.tabs[savedIndex]

            // 有 id 的条目要现场反查内容；查不到说明文章下架 / id 规则变了，只跳过这一条。
            // 没有 id 的是空 Tab（"New Tab"），不需要反查，照常建出来。
            let item: PPContentItem?
            if let itemID = saved.id {
                guard let resolved = config.contentResolver(itemID) else { continue }
                item = resolved
            } else {
                item = nil
            }

            let controller = contentViewControllerProvider()
            // 注入上报通道，和 appendTab 保持一致。
            controller.contentHost = self
            // 空 Tab 不 configure —— 它本来就没有内容可显示，标题保持默认的 "New Tab"。
            if let item = item {
                controller.configure(with: item)
            }

            // 先建立父子关系保活；view 的挂载交给 refreshUI 统一处理。
            addChild(controller)
            controller.didMove(toParent: self)

            // 正常最多只有一个预览 Tab；存档里若出现多个（脏数据 / 手工改过），只认第一个，
            // 否则「预览槽位唯一」的约定会被破坏。
            let isPreview = saved.isPreview && !didUsePreviewSlot
            if isPreview { didUsePreviewSlot = true }

            // 记下选中项在「恢复后的数组」里的位置：前面可能有条目被跳过，下标会错位。
            if savedIndex == snapshot.selectedIndex {
                restoredSelectedIndex = restoredTabs.count
            }

            restoredTabs.append(DetailTabItem(
                id: UUID().uuidString,
                item: item,
                controller: controller,
                isPreview: isPreview
            ))
        }

        guard !restoredTabs.isEmpty else { return }

        // 一次性替换数据源：不调 appendTab，避免 N 次 insert / N 次 layout。
        tabs = restoredTabs

        // 选中项兜底：存档里的下标可能因上面跳过失效内容而错位，越界就夹到合法范围。
        let fallbackIndex = min(max(snapshot.selectedIndex, 0), restoredTabs.count - 1)
        selectedTabID = restoredTabs[restoredSelectedIndex ?? fallbackIndex].id

        // 让壳与内容视图进入「有 Tab」的状态（显示 Tab 条、挂上选中的内容页）。
        refreshUI()

        // 首次滚动推迟到布局完成；见 viewDidLayoutSubviews。
        needsScrollToRestoredSelection = true

        // 恢复出来的选中项也是「当前选中项」，要通知外部同步左侧高亮，不能漏。
        notifySelectionChanged()

        // 这里绝对不写盘：上面被 resolver 判为 nil 的条目还留在存档里，
        // 此时保存会把它们永久删掉。等用户下一次真正操作 Tab 时再写。
    }

    // 把当前 Tab 状态写进存档。没开启 / 没配 resolver / 恢复中，都直接跳过。
    private func persistTabsIfNeeded() {
        // 恢复过程中不写盘（原因见 restoreTabsIfNeeded）。
        guard !isRestoringTabs else { return }

        // 只有「首次加载时确实决定要恢复」的宿主才保存：
        // 没开启、没配 resolver、加载之后才改配置的宿主，一律不碰 UserDefaults。
        guard didAttemptTabRestoration, let config = restorationConfig else { return }

        var savedTabs: [PPTabRestorationSnapshot.Tab] = []
        var selectedIndex = 0

        for tab in tabs {
            // 选中的这一份要先记下标，再 append —— 空 Tab 也存，所以下标始终对得上。
            if tab.id == selectedTabID {
                selectedIndex = savedTabs.count
            }
            // 空 Tab 也存（id 写 nil）：用户上次留着的空白工作区，恢复后应该还是空白。
            savedTabs.append(PPTabRestorationSnapshot.Tab(id: tab.item?.id, isPreview: tab.isPreview))
        }

        // 一个 Tab 都没有（用户把标签页全关了）：删键，而不是写空数组 ——
        // 删掉之后下次启动是干净的「没有历史」，语义比一个空快照更清楚。
        guard !savedTabs.isEmpty else {
            PPTabRestoration.removeSnapshot(forKey: config.persistenceKey)
            return
        }

        let snapshot = PPTabRestorationSnapshot(
            version: PPTabRestorationSnapshot.currentVersion,
            tabs: savedTabs,
            selectedIndex: selectedIndex
        )
        PPTabRestoration.saveSnapshot(snapshot, forKey: config.persistenceKey)
    }

    private func appendTab(for item: PPContentItem?, isPreview: Bool) {
        // 先确保视图（以及下面的 Tab 条 collectionView）已经加载：
        // viewDidLoad 里会做一次全量 reloadData，把当时已有的 Tab 作为“基线”交给集合视图。
        // 若此前视图还没加载过（例如宿主刚 init 完、还没上屏就被要求打开内容，
        // 典型场景是“启动时恢复上次的 Tab”），而 tabs 已经先被 append 了一个，
        // 那么 viewDidLoad 的 reloadData 会把 1 个 Tab 当成基线，
        // 紧接着下面的 insert(0) 就变成“插入前 1 个、插入后还是 1 个”，
        // 集合视图直接抛 NSInternalInconsistencyException（Invalid batch updates）。
        // 在这里主动把视图加载提到 append 之前，基线就永远是“append 之前的数量”，两边对得上。
        loadViewIfNeeded()

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

        // 新建 Tab 后它自动成为选中项：通知外部同步左侧高亮。
        notifySelectionChanged()
        // 多了一个 Tab，而且它成了选中项：快照要立刻跟上。
        persistTabsIfNeeded()
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

        // 关闭可能让选中项变成相邻 Tab，或变成“没有选中项”：通知外部同步左侧高亮。
        // （关的是未选中的 Tab 时，去重逻辑会发现选中项没变，不会重复回调。）
        notifySelectionChanged()

        // Tab 少了一个（关的可能是选中项，也可能是别的）：快照要减掉这一条。
        // 放在退出确认之前 —— 全部关光时快照应该已经被删掉，和当前状态一致。
        persistTabsIfNeeded()

        // 新增：所有 Tab 都已关闭，且外部开启了退出确认 -> 弹出“是否退出 App”确认框。
        // 无论关闭途径（Command+W 快捷键、点 Tab 上的关闭按钮）都统一生效。
        if tabs.isEmpty && showExitPromptWhenAllTabsClosed {
            presentExitConfirmationIfNeeded()
        }

        // 精细化：先删除被关的 cell。
        // 注意：delete 与 reload 不能落在同一批次的同一个 index path（两者都按批次前的状态解释）：
        // 若关的是“选中且非末位”的 tab，顶上来那个的新索引恰好等于被删的旧索引，
        // 混在同一批会撞车（NSInternalInconsistencyException）。
        // 所以删除后集合视图已与 tabs 对齐，选中态刷新放到 completion 里按新索引做。
        // 同 updateTabBar：先落布局，避免在旧 bounds（如高度刚变 0）下执行删除。
        view.layoutIfNeeded()
        collectionView.performBatchUpdates({ [weak self] in
            guard let self = self else { return }
            self.collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
        }) { [weak self] _ in
            guard let self = self else { return }
            if wasSelected, let newIndexPath = self.tabBarIndexPath(ofTabID: self.selectedTabID) {
                self.collectionView.reloadItems(at: [newIndexPath])
            }
            self.scrollToSelectedItem(animated: true)
        }
    }

    // MARK: - 私有：退出确认弹框

    // 弹出“是否退出 App”确认框：确定则退出，取消则停留在当前（空 Tab）状态。
    private func presentExitConfirmationIfNeeded() {
        let alert = UIAlertController(
            title: "是否退出 App？",
            message: "所有标签页都已关闭，是否退出应用？",
            preferredStyle: .alert
        )
        // 取消：什么都不做，留在当前页面（用户还能从左侧重新打开内容）。
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        // 退出：执行退出动作。
        alert.addAction(UIAlertAction(title: "退出", style: .destructive) { [weak self] _ in
            self?.performExit()
        })
        // 用“最顶层可 present 的控制器”来弹，避免当前已有模态（如新窗口）时 present 失败。
        topMostPresentedViewController().present(alert, animated: true)
    }

    // 找到当前能 present 弹框的最顶层控制器（沿 presentedViewController 链向下钻）。
    private func topMostPresentedViewController() -> UIViewController {
        var top: UIViewController = self
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    // 执行退出。优先使用外部注入的 exitAction；没有注入时走平台默认实现。
    private func performExit() {
        if let exitAction = exitAction {
            // 集成方自定义的退出行为（例如“回到首页”），用它即可。
            exitAction()
            return
        }
        
        // iOS/iPadOS：没有官方“退出 App”的 API，演示项目用 exit(0) 兜底。
        // 注意：生产环境的 App Store 应用不应调用 exit()，请改用 exitAction
        // 注入“回到首页 / 关闭窗口”之类的自定义行为。
//        exit(0)

    }

    // 把某个 Tab 设为预览/正式，并刷新对应 cell 的样式。
    private func setPreview(_ value: Bool, for controller: UIViewController) {
        guard let index = tabs.firstIndex(where: { $0.controller === controller }) else { return }
        tabs[index].isPreview = value
        collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        // isPreview 是快照字段：内容页一被编辑，预览变正式，存档也要跟着改。
        persistTabsIfNeeded()
    }

    // MARK: - 私有：Tab 条的精细化更新

    // 按 tab id 查它在 Tab 条里的位置（不在/为 nil 时返回 nil）。
    private func tabBarIndexPath(ofTabID id: String?) -> IndexPath? {
        guard let id = id, let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        return IndexPath(item: index, section: 0)
    }

    // 两个 Tab 底色（tabSelectedBackgroundColor / tabUnselectedBackgroundColor）改动后调用：
    // 把已有 Tab 的单元格重刷一遍，颜色立刻生效。
    // 只 reload 单元格、不做 reloadData —— 免得整条 Tab 条重建重排。
    private func applyTabBarColors() {
        // 视图还没加载（例如刚 init 完就赋值）时数据源尚未建立，直接跳过；
        // 之后首次 configure 读到的就是新颜色，设置不会丢。
        guard isViewLoaded, !tabs.isEmpty else { return }
        let indexPaths = tabs.indices.map { IndexPath(item: $0, section: 0) }
        collectionView.reloadItems(at: indexPaths)
    }

    // Tab 条更新遵循“能少刷就少刷”：切 tab / 开 / 关都不全量 reloadData，
    // 而是按需 reload / insert / delete 受影响的 item，避免全部 cell 重建与全量布局。
    // 滚动放在 performBatchUpdates 的 completion 里：此时布局已就绪，
    // 无需再 DispatchQueue.main.async 延后滚动。
    private func updateTabBar(reload: [IndexPath], insert: [IndexPath], delete: [IndexPath]) {
        // 视图还没上屏（宿主刚 init 完就被预开了 Tab、或启动阶段恢复）时不做增量更新。
        // 原因：这种情况下 collectionView 的条数会在布局时一次性同步成最新值，
        // 紧接着再 insert / delete 就会被判成「更新前后条数对不上」，直接抛
        // NSInternalInconsistencyException（Invalid batch updates）。
        // 反正屏幕上看不到这一帧，全量刷新语义一样、代价还更小。
        guard collectionView.window != nil, collectionView.bounds.width > 0 else {
            collectionView.reloadData()
            return
        }

        // 关键：Tab 条可能刚从隐藏/高度 0 恢复（约束常量刚在 refreshUI 里改过，帧还没更新），
        // 必须先落一次布局拿到真实尺寸；否则 insert/delete 会在“高度 0 的旧 bounds”下执行：
        // flow layout 不会去问 sizeForItemAt，新 cell 宽高全是 0，且之后撑回 44 也不会自动纠正。
        view.layoutIfNeeded()
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
        // 分隔线用语义色：浅色下是原来那条几乎看不见的 0.97，深色下自动换成半透明白，
        // 不然纯黑的背景上会挂着一条刺眼的白线。
        separatorView.backgroundColor = .pp_hairlineSeparator

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        // 内容容器跟着系统背景走：浅色白、深色黑（原来是写死的白色）。
        contentContainerView.backgroundColor = .pp_systemBackground

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = "← 请从左侧选择文章"
        placeholderLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        placeholderLabel.textColor = .pp_tertiaryLabel

        // 侧栏展开/折叠按钮：与 Tab 条等高、位于其最左侧。
        sidebarToggleButton.translatesAutoresizingMaskIntoConstraints = false
        // 图标颜色跟随文字色：浅色近黑、深色近白（原来是写死的 0.35 深灰，深色下会看不见）。
        sidebarToggleButton.tintColor = .pp_label
//        sidebarToggleButton.backgroundColor = UIColor(red: 0.91, green: 0.91, blue: 0.91, alpha: 1.00)
        sidebarToggleButton.addTarget(self, action: #selector(sidebarButtonTapped), for: .touchUpInside)
        updateSidebarButtonIcon()

        view.addSubview(collectionView)
        view.addSubview(separatorView)
        view.addSubview(contentContainerView)
        view.addSubview(sidebarToggleButton)
        contentContainerView.addSubview(placeholderLabel)

        let collectionViewHeightConstraint = collectionView.heightAnchor.constraint(equalToConstant: DetailTabBarMetrics.barHeight)
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
        collectionViewHeightConstraint?.constant = hasTabs ? DetailTabBarMetrics.barHeight : 0
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

    // 关闭按钮用 .custom 而不是 .system，是踩过坑的：
    // Mac Catalyst 会给 .system 按钮自动配一套「指针悬停外观」，鼠标压上去时系统会自己给按钮铺一层高亮背景，
    // 那层背景叠在 Tab 底色上不受我们控制 —— 表现就是「x 的显隐正常，但悬停时的底色不对 / 被盖掉」。
    // .custom 按钮没有这层系统外观，整个 Tab 的底色变化完全由我们自己说了算（标题颜色本来就已手动指定，不受影响）。
    private let closeButton = UIButton(type: .custom)

    var onClose: (() -> Void)?

    // 鼠标悬浮在本 Tab 上时，整个 Tab 要变的底色（= 宿主上的 tabSelectedBackgroundColor），
    // 由 configure 从入参里取一份存下来。目前只有 Mac Catalyst 用得上它，但无条件声明，省得在 configure 里写条件编译。
    private var hoverBackgroundColor: UIColor = .clear

    // 没被悬浮时本 Tab 原本的底色（选中 / 未选中不一样），鼠标离开本 Tab 后要还原回它。
    private var normalBackgroundColor: UIColor = .clear

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        contentView.layer.cornerRadius = DetailTabBarMetrics.cellCornerRadius
        // 只圆上面两个角、下面两个角保持直角：单元格底边与 Tab 条底边对齐，
        // 圆底角会在底边留出两个缺口，看起来像浮在空中；直角则像标签页“长”在底边上。
        contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
//        contentView.layer.borderWidth = 1
//        contentView.layer.borderColor = UIColor(white: 0.80, alpha: 0.5).cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 14)//, weight: .semibold)
        // 文字用语义色：浅色近黑、深色近白（原来是写死的黑色，深色下等于看不见）。
        titleLabel.textColor = .pp_label
        titleLabel.lineBreakMode = .byTruncatingTail

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("x", for: .normal)
        // 关闭按钮的 x 也走语义色，比正文浅一档，不抢标题的视线。
        closeButton.setTitleColor(.pp_secondaryLabel, for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        #if targetEnvironment(macCatalyst)
        // Mac 上是用鼠标操作的：默认先把关闭按钮藏起来、底色用「未悬浮」的那份，
        // 鼠标挪到本 Tab 上才把 x 露出来、底色点亮，对齐网页里 CSS hover 的效果；
        // 触摸平台上没有悬浮一说，保持一直显示（下面这些只在 Catalyst 编译）。
        resetHoverAppearance()
        // UIHoverGestureRecognizer 只在鼠标进出 / 移动时回调，不会抢走点击事件，所以放心挂在单元格上。
        // 挂在单元格（而不是按钮）上，是因为“悬浮区”是整个 Tab：指针落在标题上也算悬浮。
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(handleCellHover(_:))))
        #endif

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

    // 单元格会被复用：上一次悬浮留下的“按钮已显示 / 底色已点亮”状态必须清掉，
    // 否则快速滚动时会闪出带着 x 或带着亮底色的错误帧（复用时指针通常不会再触发一次 .ended）。
    override func prepareForReuse() {
        super.prepareForReuse()
        #if targetEnvironment(macCatalyst)
        resetHoverAppearance()
        #endif
    }

    #if targetEnvironment(macCatalyst)

    // 把单元格恢复成“没被悬浮”的样子：藏起关闭按钮 + 把 Tab 底色还原回原本的色。
    private func resetHoverAppearance() {
        closeButton.isHidden = true
        contentView.backgroundColor = normalBackgroundColor
    }

    // 鼠标在本单元格上进出 / 移动时回调。
    // 悬浮的判定粒度是「整个 Tab」：指针只要落在单元格里（标题上、按钮上都算），就露出关闭按钮并把底色点亮。
    @objc private func handleCellHover(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            // 指针进了这个 Tab：露出关闭按钮，同时把整个 Tab 的底色换成「选中 Tab 的底色」，
            // 效果就是鼠标划过的 Tab 会亮一下（对齐网页里的 CSS hover）。
            closeButton.isHidden = false
            contentView.backgroundColor = hoverBackgroundColor

        case .ended, .cancelled:
            // 指针离开单元格；cancelled 是指针被系统收走（例如切到别的窗口），同样按离开处理。
            resetHoverAppearance()

        default:
            break
        }
    }

    #endif

    // 底色不再写死在单元格里：由宿主把两个公开变量传进来，
    // 集成方改宿主上的 tabSelectedBackgroundColor / tabUnselectedBackgroundColor 就能换肤。
    // 单元格会被复用，所以每次配置都要重新赋一次色，不能只在 init 里设。
    func configure(
        title: String,
        selected: Bool,
        isPreview: Bool,
        selectedBackgroundColor: UIColor,
        unselectedBackgroundColor: UIColor
    ) {
        titleLabel.text = title
        // 先记住「非悬浮时本来该是什么色」，再铺上去；鼠标离开本 Tab 时要以它为基准还原。
        normalBackgroundColor = selected ? selectedBackgroundColor : unselectedBackgroundColor
        contentView.backgroundColor = normalBackgroundColor
        // 记一份选中底色给悬浮状态用：鼠标停在本 Tab 上时，整个 Tab 的底色要变成选中 Tab 的底色。
        hoverBackgroundColor = selectedBackgroundColor
        // 预览 Tab 用斜体，强调“可复用”；正式 Tab 用正常字体（半粗）。
        titleLabel.font = isPreview
            ? UIFont.italicSystemFont(ofSize: 14)
            : UIFont.systemFont(ofSize: 14, weight: .semibold)
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
