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

    // 分割线相关常量。
    private let dividerHitWidth: CGFloat = 12   // 抓取区宽度（命中范围，越大越好抓）
    private let minLeftWidth: CGFloat = 220     // 左栏最小宽度
    private let minRightWidth: CGFloat = 320    // 右栏最小宽度

    // 右侧唯一的详情宿主（多 Tab 都在它里面）。内容页工厂由外部注入，转交给它。
    private let detailHost: DetailHostViewController

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
        view.backgroundColor = .white
        setupLayout()
        embed(leftNavigationController, in: leftContainerView)
        embed(detailHost, in: rightContainerView)

        // 套用“启动默认值”：若外部在加载前把 isLeftSidebarVisible 设为 false，
        // isSidebarHidden 此时已是 true，这里按折叠状态布局一次（不带动画）。
        applySidebarLayout(animated: false)
    }

    // MARK: - 布局

    private func setupLayout() {
        [leftContainerView, rightContainerView, dividerHandleView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        leftContainerView.backgroundColor = .white
        rightContainerView.backgroundColor = .white
        // 抓取区本身透明，真正的“线”由里面的 dividerLineView 画出。
        dividerHandleView.backgroundColor = .clear

        // 可见细线：放在抓取区正中央，宽 1pt。
        dividerLineView.translatesAutoresizingMaskIntoConstraints = false
        dividerLineView.backgroundColor = UIColor(white: 0.85, alpha: 1.0)
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
            dot.backgroundColor = UIColor(white: 0.55, alpha: 1.0)
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
            : UIColor(white: 0.85, alpha: 1.0)
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
        let hidden = !visible
        guard hidden != isSidebarHidden else { return }
        isSidebarHidden = hidden
        // 同步详情宿主侧栏按钮的图标。
        detailHost.setSidebarCollapsed(hidden)
        applySidebarLayout(animated: animated)
    }

    /// 在展开/折叠之间切换（带动画）。
    public func toggleLeftSidebar() {
        setLeftSidebarVisible(!isLeftSidebarVisible, animated: true)
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
