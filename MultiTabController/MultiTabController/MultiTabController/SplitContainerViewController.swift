import UIKit

// 在 Mac Catalyst 下导入 AppKit，用于把鼠标光标设为“左右调整大小”。
#if targetEnvironment(macCatalyst)
import AppKit
#endif

// MARK: - SplitContainerViewController
// 模仿 NewsSplitDemo 的 SplitContainerViewController：iPad / Mac Catalyst 的根控制器。
// 左栏 = 由调用方注入的任意 UIViewController（例如 PPTabBarController 包着若干列表，各自装上 PPSplitContentRouter）；
// 右栏 = 一个 DetailHostViewController（右侧多 Tab 详情宿主，承载 VS Code 预览/正式策略）。
// 这样“浏览器式多 Tab”被下沉到右侧详情宿主里，左栏在切 Tab 时始终不动。
// 本容器只负责把左侧“打开内容”的意图转交右侧详情宿主，不感知任何具体业务内容（库保持纯净）。
public final class SplitContainerViewController: UIViewController {

    private let leftContainerView = UIView()
    private let rightContainerView = UIView()

    // 分割线：dividerHandleView 是较宽的“抓取区”（透明，方便鼠标/手指命中），
    // 中间的 dividerLineView 才是真正可见的细线；hoverGripView 是悬浮时出现的“拖动标志”。
    private let dividerHandleView = UIView()
    private let dividerLineView = UIView()
    private let hoverGripView = UIView()

    // 左栏宽度约束（存为属性，拖动时动态修改它的 constant 即可改变左右比例）。
    private var leftWidthConstraint: NSLayoutConstraint!

    // 左栏的 leading 约束（存为属性）：折叠左栏时不改宽度、而是把它的 constant 改为负值，
    // 让左栏 + 分割线整体滑出屏幕左侧（模仿 UISplitViewController 的 hideColumn）；
    // 展开时再改回 0。这样左栏内容不会因宽度变小而回流重排。
    private var leftLeadingConstraint: NSLayoutConstraint!

    // 拖动时的临时状态：记录起始宽度与指针起始位置，按位移增量调整。
    private var dragStartLeftWidth: CGFloat = 0
    private var dragStartLocationX: CGFloat = 0

    /// 左栏是否可见（对外公开的唯一控制入口）。
    /// 读取得到当前真实状态；设置即可展开/折叠（视图已加载时立即套用，无动画）。
    /// 需要带动画请调用 setLeftSidebarVisible(_:animated:) 或 toggleLeftSidebar()。
    public var isLeftSidebarVisible: Bool {
        get { !isSidebarHidden }
        set { setLeftSidebarVisible(newValue, animated: false) }
    }

    // 内部唯一运行时状态：是否隐藏左栏。
    private var isSidebarHidden = false

    // MARK: - 侧栏状态持久化（单实例覆盖）
    //
    // 三个属性默认都是 nil，意思是「不表态，跟随全局 PPSidebarRestoration」。
    // 和 DetailHostViewController 的 Tab 恢复一样，只在 view 第一次加载（viewDidLoad）时求值一次：
    // 在这之前设置立即生效；在这之后设置不会补读盘，也不会换保存用的键，
    // 避免出现「从 A 键读、往 B 键写」的错位。

    /// 本容器是否在首次加载时还原上次的侧栏折叠状态。
    /// - `nil`（默认）：跟随全局 `PPSidebarRestoration.isEnabled`
    /// - `true` / `false`：只对当前容器生效，覆盖全局
    public var restoresSidebarStateOnLaunch: Bool?

    /// 本容器专用的存档键。`nil`（默认）= 用全局 `PPSidebarRestoration.persistenceKey`。
    /// 空字符串表示本容器不读也不写。
    ///
    /// 一个 App 里同时存在多个分栏容器（多窗口）时必须分开，否则两边会互相覆盖对方的状态。
    /// 多数情况下用下面的 `sidebarStatePersistenceIdentity` 更省事，不用自己拼键。
    /// - Note: 不能在上屏时自动按窗口 / 场景拼后缀，因为那一刻容器还没进窗口，view.window 是 nil。
    public var sidebarStatePersistenceKey: String?

    /// 本容器的身份标识，用来在基础键后面拼一段后缀，让多个容器各存一份、互不覆盖。
    ///
    /// 最终使用的键是 `（sidebarStatePersistenceKey ?? PPSidebarRestoration.persistenceKey）+ "." + identity`。
    /// - `nil`（默认）/ 空字符串：不拼后缀，直接用基础键。这时多个容器会共用同一把键、互相覆盖，
    ///   单窗口 App 不受影响。
    /// - 基础键被设成空字符串时整个能力关闭，这条身份也就无处可拼。
    ///
    /// ```swift
    /// // 每个窗口一个容器时，用场景自带的持久标识
    /// split.sidebarStatePersistenceIdentity = session.persistentIdentifier
    /// ```
    ///
    /// - Important: 必须是**跨启动稳定**的值。用每次启动新生成的 `UUID()` 会导致每次写到一个新键上，
    ///   看起来像「永远恢复不了」。`UISceneSession.persistentIdentifier` 是符合要求的。
    /// - Note: 和另外两个属性一样只在 `viewDidLoad` 求值一次。运行期改它不会换键、也不会重新读盘，
    ///   已经上屏的容器会继续用当初拼出来的那把键读写。
    public var sidebarStatePersistenceIdentity: String?

    // 首次加载时求值出来的存档键；nil = 本容器不持久化（开关关着 / 键为空）。
    private var resolvedSidebarStateKey: String?
    // 是否已经求值过配置。无论开关开没开都会置位：之后运行期再打开全局开关，也不会追溯这个容器。
    private var didResolveSidebarState = false
    // 集成方在「读存档之前」显式调过 setLeftSidebarVisible：以现场为准，不拿存档覆盖。
    private var hasExplicitSidebarStateBeforeRestore = false

    // 分割线相关常量。
    private let dividerHitWidth: CGFloat = 12   // 抓取区宽度（命中范围，越大越好抓）
    private let minLeftWidth: CGFloat = 220     // 左栏最小宽度
    private let minRightWidth: CGFloat = 320    // 右栏最小宽度

    // 右侧唯一的详情宿主（多 Tab 都在它里面）。内容页工厂由外部注入，转交给它。
    // 公开出来，是为了让集成方能直接改宿主上的外观 / 行为项，例如
    // detailHost.tabSelectedBackgroundColor、detailHost.deduplicateOpenedItems。
    public let detailHost: DetailHostViewController

    // 分栏路由：列表发出的“打开内容”意图由它转交给右侧 detailHost。
    private let splitRouter: PPSplitContentRouter

    // 左栏的导航控制器（包住 PPTabBarController，提供导航条）。
    private let leftNavigationController: UINavigationController

    /// 用外部提供的左侧内容控制器（例如 PPTabBarController 包着若干列表）、分栏路由与内容页工厂初始化。
    /// 本容器不创建任何业务列表或数据，只负责：
    ///   1. 把 router.detailHostResolver 指向右侧详情宿主，使“打开内容”能落到右侧；
    ///   2. 响应右侧详情宿主侧栏按钮的展开/折叠请求。
    /// 列表控制器及其 router 由调用方（宿主 App）自行构建。
    public init(
        leftViewController: UIViewController,
        router: PPSplitContentRouter,
        contentViewControllerProvider: @escaping PPContentViewControllerProvider
    ) {
        self.splitRouter = router
        self.leftNavigationController = UINavigationController(rootViewController: leftViewController)
        self.detailHost = DetailHostViewController(contentViewControllerProvider: contentViewControllerProvider)

        super.init(nibName: nil, bundle: nil)

        // 把“打开内容”解析到右侧的详情宿主。
        router.detailHostResolver = { [weak self] _ in
            self?.detailHost
        }

        // 右侧详情宿主里侧栏按钮的点击 -> 由本容器执行左栏的展开/折叠动画。
        detailHost.onToggleSidebarRequest = { [weak self] in
            self?.toggleLeftSidebar()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 库要对外暴露类型，故声明为 public；覆盖系统 open 方法用 internal 亦可，这里统一对外口径。
    public override func viewDidLoad() {
        super.viewDidLoad()
        // 根视图底色跟随系统外观：浅色白、深色黑。
        view.backgroundColor = .pp_systemBackground
        setupLayout()
        embed(leftNavigationController, in: leftContainerView)
        embed(detailHost, in: rightContainerView)

        // 先读回上次的折叠状态，再套布局。顺序不能反：
        // 如果先按「展开」排一次再改成折叠，第一帧会明显闪一下。
        restoreSidebarStateIfNeeded()

        // 套用“启动状态”：恢复值，或外部在加载前显式设的值。不带动画。
        applySidebarLayout(animated: false)
    }

    // MARK: - 布局

    private func setupLayout() {
        [leftContainerView, rightContainerView, dividerHandleView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        // 左右两栏的底色也走语义色：深色下如果还留白，就会变成两块发光的白板。
        leftContainerView.backgroundColor = .pp_systemBackground
        rightContainerView.backgroundColor = .pp_systemBackground
        // 抓取区本身透明，真正的“线”由里面的 dividerLineView 画出。
        dividerHandleView.backgroundColor = .clear

        // 可见细线：放在抓取区正中央，宽 1pt。
        dividerLineView.translatesAutoresizingMaskIntoConstraints = false
        dividerLineView.backgroundColor = .pp_separator
        dividerHandleView.addSubview(dividerLineView)

        // 悬浮“拖动标志”：三个小圆点，平时隐藏，鼠标移到分割线上才出现。
        setupGrip()

        view.addSubview(leftContainerView)
        view.addSubview(dividerHandleView)
        view.addSubview(rightContainerView)

        // 关键：把左栏宽度约束存成属性，拖动时改它的 constant。
        leftWidthConstraint = leftContainerView.widthAnchor.constraint(equalToConstant: 320)
        // 关键：把左栏 leading 约束存成属性，折叠/展开时改它的 constant 做滑动动画。
        leftLeadingConstraint = leftContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0)

        NSLayoutConstraint.activate([
            leftContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            leftLeadingConstraint,
            leftContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftWidthConstraint,

            dividerHandleView.topAnchor.constraint(equalTo: view.topAnchor),
            dividerHandleView.leadingAnchor.constraint(equalTo: leftContainerView.trailingAnchor),
            dividerHandleView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dividerHandleView.widthAnchor.constraint(equalToConstant: dividerHitWidth),

            rightContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            rightContainerView.leadingAnchor.constraint(equalTo: dividerHandleView.trailingAnchor),
            rightContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 细线垂直撑满、水平居中（看起来就是一条细分隔线）。
        NSLayoutConstraint.activate([
            dividerLineView.centerXAnchor.constraint(equalTo: dividerHandleView.centerXAnchor),
            dividerLineView.topAnchor.constraint(equalTo: dividerHandleView.topAnchor),
            dividerLineView.bottomAnchor.constraint(equalTo: dividerHandleView.bottomAnchor),
            dividerLineView.widthAnchor.constraint(equalToConstant: 1)
        ])

        // 拖动标志（小圆点）整体居中在抓取区。
        NSLayoutConstraint.activate([
            hoverGripView.centerXAnchor.constraint(equalTo: dividerHandleView.centerXAnchor),
            hoverGripView.centerYAnchor.constraint(equalTo: dividerHandleView.centerYAnchor)
        ])

        // 绑定拖动 + 悬浮手势。
        setupDividerInteractions()
    }

    // 在抓取区中央放三个小圆点，作为“可以拖动”的视觉提示。
    private func setupGrip() {
        hoverGripView.translatesAutoresizingMaskIntoConstraints = false
        hoverGripView.backgroundColor = .clear
        hoverGripView.isHidden = true   // 平时隐藏，悬浮时才显示
        dividerHandleView.addSubview(hoverGripView)

        let dotSize: CGFloat = 4
        let spacing: CGFloat = 5
        var previous: UIView?
        for _ in 0..<3 {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            // 悬浮提示的三个小圆点：浅色下是中灰，深色下换成更亮的灰（0.55 的灰在纯黑上看不清）。
            dot.backgroundColor = .pp_adaptive(
                light: UIColor(white: 0.55, alpha: 1.0),
                dark: UIColor(white: 0.75, alpha: 1.0)
            )
            dot.layer.cornerRadius = dotSize / 2
            hoverGripView.addSubview(dot)
            // 竖向排列：每个圆点左右撑满（leading/trailing 对齐容器），
            // 自身宽高固定为 dotSize，圆点之间靠 top 串联，形成一列。
            NSLayoutConstraint.activate([
                dot.leadingAnchor.constraint(equalTo: hoverGripView.leadingAnchor),
                dot.trailingAnchor.constraint(equalTo: hoverGripView.trailingAnchor),
                dot.widthAnchor.constraint(equalToConstant: dotSize),
                dot.heightAnchor.constraint(equalToConstant: dotSize)
            ])
            if let prev = previous {
                // 第二个、第三个圆点：顶部对齐上一个圆点的底部，中间留 spacing 间距
                dot.topAnchor.constraint(equalTo: prev.bottomAnchor, constant: spacing).isActive = true
            } else {
                // 第一个圆点：顶部对齐容器顶部
                dot.topAnchor.constraint(equalTo: hoverGripView.topAnchor).isActive = true
            }
            previous = dot
        }
        if let last = previous {
            // 最后一个圆点底部对齐容器底部，让整列圆点垂直居中在容器内
            last.bottomAnchor.constraint(equalTo: hoverGripView.bottomAnchor).isActive = true
        }
        // 容器宽度固定为圆点直径（竖向排列时横向只占一个圆点宽）
        hoverGripView.widthAnchor.constraint(equalToConstant: dotSize).isActive = true
    }

    // 给分割线绑定：1) 拖动手势；2) 悬浮手势（iOS 13.4+ 指针/鼠标）。
    private func setupDividerInteractions() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        dividerHandleView.addGestureRecognizer(pan)

        if #available(iOS 13.4, *) {
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
            dividerHandleView.addGestureRecognizer(hover)
        }
    }

    // 拖动分割线：按手指/指针的水平位移，实时改变左栏宽度（带上下限钳制）。
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            // 记录起点：起始宽度 + 起始位置。
            dragStartLeftWidth = leftWidthConstraint.constant
            dragStartLocationX = gesture.location(in: view).x
            updateDividerAppearance(hovering: true)
        case .changed:
            let currentX = gesture.location(in: view).x
            let delta = currentX - dragStartLocationX
            leftWidthConstraint.constant = clampedLeftWidth(dragStartLeftWidth + delta)
        case .ended, .cancelled, .failed:
            updateDividerAppearance(hovering: false)
        default:
            break
        }
    }

    // 悬浮分割线：出现“拖动标志”，并在 Mac 上把鼠标光标设为左右调整大小。
    @available(iOS 13.4, *)
    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        let isHovering = (gesture.state == .began || gesture.state == .changed)
        updateDividerAppearance(hovering: isHovering)

        #if targetEnvironment(macCatalyst)
        if isHovering {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.arrow.set()
        }
        #endif
    }

    // 根据是否悬浮，切换分割线颜色与小圆点显隐。
    private func updateDividerAppearance(hovering: Bool) {
        dividerLineView.backgroundColor = hovering
            ? UIColor.systemBlue
            : .pp_separator
        hoverGripView.isHidden = !hovering
    }

    // 把左栏宽度钳制在 [minLeftWidth, 视图可用宽度 - 分割线 - minRightWidth] 之间。
    private func clampedLeftWidth(_ width: CGFloat) -> CGFloat {
        let maxLeft = view.bounds.width - dividerHitWidth - minRightWidth
        return max(minLeftWidth, min(width, maxLeft))
    }

    // MARK: - 左栏展开 / 折叠（模仿 UISplitViewController 的 showColumn / hideColumn）

    /// 展开/折叠左栏（可带动画）。
    /// 模仿 UISplitViewController 的 showColumn / hideColumn：不改左栏宽度（避免列表内容回流重排），
    /// 而是把 leading 约束的 constant 改成负值，让左栏连同分割线整体滑出屏幕左侧；
    /// 由于分割线、右栏的约束都锚定在左栏上，右栏会自动向左扩展填满空间。
    /// 读取当前真实状态请用 isLeftSidebarVisible（计算属性）。
    public func setLeftSidebarVisible(_ visible: Bool, animated: Bool) {
        // 在读存档之前被调用，说明是集成方在声明「启动默认值」（文档一直支持这种用法）。
        // 记下来，viewDidLoad 里就不再让存档覆盖它。要放在 guard 之前，否则设成和默认值相同会被漏掉。
        if !didResolveSidebarState {
            hasExplicitSidebarStateBeforeRestore = true
        }

        let hidden = !visible
        // 状态没变就提前返回，布局和写盘都不用做。
        // 这里不会漏写盘：只有真的发生变化才需要写；加载前的显式设置由 restoreSidebarStateIfNeeded 负责落盘。
        guard hidden != isSidebarHidden else { return }
        isSidebarHidden = hidden
        // 同步详情宿主侧栏按钮的图标。
        detailHost.setSidebarCollapsed(hidden)
        applySidebarLayout(animated: animated)

        // 侧栏按钮点击（onToggleSidebarRequest -> toggleLeftSidebar）、
        // 集成方直接调 isLeftSidebarVisible / setLeftSidebarVisible、toggleLeftSidebar()，
        // 三条路径最后都汇到这里，所以写盘只要这一个出口。
        persistSidebarStateIfNeeded()
    }

    /// 在展开/折叠之间切换（带动画）。
    public func toggleLeftSidebar() {
        setLeftSidebarVisible(!isLeftSidebarVisible, animated: true)
    }

    // MARK: - 私有：侧栏状态恢复 / 保存

    // 把「全局开关」和「本容器的三个覆盖项」合并成一份配置，只在 viewDidLoad 求值一次。
    private func restoreSidebarStateIfNeeded() {
        // viewDidLoad 只会走一次；这个标记是给「以后有人把调用挪到别处」留的保险。
        guard !didResolveSidebarState else { return }
        // 不管开关开着还是关着都置位：之后再把全局开关打开，也不会追溯这个已经上屏的容器。
        didResolveSidebarState = true

        // 开关是三态的：容器说过就听容器的，没表态才看全局。
        let enabled = restoresSidebarStateOnLaunch ?? PPSidebarRestoration.isEnabled
        guard enabled else { return }

        // 基础键同理：容器给了自定义键就用它，否则落到全局键上。
        let baseKey = sidebarStatePersistenceKey ?? PPSidebarRestoration.persistenceKey
        // 再拼身份后缀。resolvedKey 里已经处理了「基础键为空 → 不持久化」和「身份为空 → 不拼」，
        // 所以这里拿到的就是最终要用的键；它不会再为空，也就不需要另外判空。
        guard let key = PPSidebarRestoration.resolvedKey(base: baseKey,
                                                         identity: sidebarStatePersistenceIdentity) else { return }
        resolvedSidebarStateKey = key

        // 集成方在加载前显式设过：以现场为准，并把这份选择写回存档。
        // 不写回的话，存档里会一直留着上一次的旧值，例如上次是折叠、这次业务要求默认展开。
        if hasExplicitSidebarStateBeforeRestore {
            PPSidebarRestoration.saveCollapsed(isSidebarHidden, forKey: key)
            return
        }

        // 没存过 / 脏数据都返回 nil：静默按默认的展开状态走，不清坏数据。
        guard let savedCollapsed = PPSidebarRestoration.loadCollapsed(forKey: key) else { return }

        // 只改状态，布局统一交给 viewDidLoad 末尾那次 applySidebarLayout(animated: false)。
        isSidebarHidden = savedCollapsed
        // 同步宿主内部的折叠标记，保持和真实状态一致（本次不改按钮图标，但标记不能歪）。
        detailHost.setSidebarCollapsed(savedCollapsed)
    }

    // 把当前折叠状态写进存档。没开启 / 键为空 / 还没求值，都直接跳过。
    private func persistSidebarStateIfNeeded() {
        guard didResolveSidebarState, let key = resolvedSidebarStateKey else { return }
        PPSidebarRestoration.saveCollapsed(isSidebarHidden, forKey: key)
    }

    // 把当前 isSidebarHidden 状态套用到约束上（视图加载后才有意义）。
    private func applySidebarLayout(animated: Bool) {
        guard isViewLoaded else { return }
        // 折叠：向左平移“左栏宽度 + 分割线抓取区宽度”，正好完全移出屏幕；展开：回到 0。
        leftLeadingConstraint.constant = isSidebarHidden
            ? -(leftWidthConstraint.constant + dividerHitWidth)
            : 0

        let apply = { [weak self] in
            guard let self = self else { return }
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: apply)
        } else {
            apply()
        }
    }

    // childViewController 成为当前页面的子控制器，并且它的 View 会完全填满 containerView。
    private func embed(_ childViewController: UIViewController, in containerView: UIView) {
        addChild(childViewController)
        childViewController.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(childViewController.view)
        // 让 childViewController.view 的四条边分别贴住 containerView 的四条边
        NSLayoutConstraint.activate([
            childViewController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            childViewController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            childViewController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            childViewController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        //告诉 childViewController：“你已经正式加入 self 这个父控制器了”
        childViewController.didMove(toParent: self)
    }
}
