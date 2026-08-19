import UIKit

// MARK: - RootContainerViewController
// 根容器：根据设备类型选择 iPad/Mac 分屏布局 或 iPhone Tab布局
class RootContainerViewController: UIViewController {

    // iPad/Mac 下的多 Tab 管理器（类浏览器）
    private var browserTabManager: BrowserTabManagerViewController?
    // iPhone 下直接用系统 UITabBarController
    private var iPhoneTabBarController: UITabBarController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupLayout()
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

    // MARK: iPhone - UITabBarController 布局
    private func setupiPhoneTabBarLayout() {
        let tabBar = UITabBarController()

        let techListVC = ArticleListViewController(articles: DataStore.techArticles, title: "Tech")
        let techNav = UINavigationController(rootViewController: techListVC)
        techNav.tabBarItem = UITabBarItem(title: "Tech", image: UIImage(systemName: "laptopcomputer"), tag: 0)

        let newsListVC = ArticleListViewController(articles: DataStore.newsArticles, title: "News")
        let newsNav = UINavigationController(rootViewController: newsListVC)
        newsNav.tabBarItem = UITabBarItem(title: "News", image: UIImage(systemName: "newspaper"), tag: 1)

        tabBar.viewControllers = [techNav, newsNav]
        iPhoneTabBarController = tabBar

        addChild(tabBar)
        tabBar.view.frame = view.bounds
        tabBar.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tabBar.view)
        tabBar.didMove(toParent: self)
    }
}
