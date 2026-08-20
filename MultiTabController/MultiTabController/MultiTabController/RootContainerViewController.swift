import UIKit

// MARK: - RootContainerViewController
// 可复用的根容器组件：
//   - 对外暴露 init(viewControllers:titles:)，由调用方传入“任意子控制器数组 + 对应标题”；
//   - 内部根据设备类型选择 iPad/Mac 分屏浏览器布局，或 iPhone 的 UITabBarController 布局。
// 这样它不再限定必须是 ArticleListViewController，而是“任何 UIViewController 都能当一个 Tab”。
class RootContainerViewController: UIViewController {

    // 外部传入的子控制器数组（例如 [TechVC, NewsVC]）。
    // iPhone 分支会直接把它赋值给 tabBar.viewControllers。
    private let contentViewControllers: [UIViewController]
    // 与上面数组一一对应的 Tab 标题（例如 ["Tech", "News"]）。
    private let tabTitles: [String]

    // iPad/Mac 下的多 Tab 管理器（类浏览器，每个 Tab 是一个分屏）
    private var browserTabManager: BrowserTabManagerViewController?
    // iPhone 下直接用系统 UITabBarController
    private var iPhoneTabBarController: UITabBarController?

    // 指定初始化器：传入子控制器数组和对应的标题。
    // 约定：数组与标题按索引一一对应；数量不一致时以较小数目为准。
    init(viewControllers: [UIViewController], titles: [String]) {
        self.contentViewControllers = viewControllers
        self.tabTitles = titles
        super.init(nibName: nil, bundle: nil)
        // 预先为每个子控制器生成对应的 UITabBarItem（标题取自 titles 数组）
        setupTabBarItems()
    }

    // 便捷初始化器（无参）：保留原来的默认行为 —— 内置一个 Tech / News 示例。
    // 这样 AppDelegate 里原来的 RootContainerViewController() 调用依然可用。
    convenience init() {
        let techVC = ArticleListViewController(articles: DataStore.techArticles, title: "Tech")
        let techNav = UINavigationController(rootViewController: techVC)

        let newsVC = ArticleListViewController(articles: DataStore.newsArticles, title: "News")
        let newsNav = UINavigationController(rootViewController: newsVC)

        // 把包装好的导航控制器数组与标题，交给指定初始化器
        self.init(viewControllers: [techNav, newsNav], titles: ["Tech", "News"])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupLayout()
    }

    // 给每个子控制器设置 UITabBarItem：标题取自 titles，tag 用索引，图片暂时留空。
    private func setupTabBarItems() {
        for (index, vc) in contentViewControllers.enumerated() {
            let title = index < tabTitles.count ? tabTitles[index] : "Tab \(index + 1)"
            vc.tabBarItem = UITabBarItem(title: title, image: nil, tag: index)
        }
    }

    private func setupLayout() {
        switch DeviceHelper.currentLayout {
        case .iPadOrMac:
            setupBrowserTabLayout()
        case .iPhone:
            setupiPhoneTabBarLayout()
        }
    }

    // MARK: iPad/Mac - 带多Tab的分屏浏览器布局
    private func setupBrowserTabLayout() {
        let manager = BrowserTabManagerViewController()
        browserTabManager = manager
        addChild(manager)
        manager.view.frame = view.bounds
        manager.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(manager.view)
        manager.didMove(toParent: self)
    }

    // MARK: iPhone - UITabBarController 布局（由外部传入的子控制器数组驱动）
    private func setupiPhoneTabBarLayout() {
        let tabBar = UITabBarController()

        // 直接把外部传入的子控制器数组赋值给 tabBar.viewControllers，
        // 不再限定为 ArticleListViewController。
        // 每个 VC 的 UITabBarItem 已在 setupTabBarItems() 中设置好。
        tabBar.viewControllers = contentViewControllers

        iPhoneTabBarController = tabBar
        addChild(tabBar)
        tabBar.view.frame = view.bounds
        tabBar.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tabBar.view)
        tabBar.didMove(toParent: self)
    }
}
