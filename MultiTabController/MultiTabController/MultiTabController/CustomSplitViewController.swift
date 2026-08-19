import UIKit

// MARK: - CustomSplitViewController
// 用 addChild 手动实现左右分屏：
//   左侧：UITabBarController（内含2个 NavigationController+ListVC）
//   右侧：DetailViewController
class CustomSplitViewController: UIViewController {

    // 回调：用于通知父容器（BrowserTabManager）打开新 Tab 或新窗口
    var onOpenNewTab: ((Article) -> Void)?
    var onOpenNewWindow: ((Article) -> Void)?

    private let leftWidth: CGFloat = 320
    private let dividerWidth: CGFloat = 1

    // 左侧容器
    private let leftContainerView = UIView()
    // 右侧容器
    private let rightContainerView = UIView()
    // 分隔线
    private let dividerView = UIView()

    // 左侧 TabBarController（包含2个Tab）
    private var leftTabBarController: UITabBarController!
    // 右侧详情
    private var detailVC: DetailViewController!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupContainerViews()
        setupLeftSide()
        setupRightSide()
    }

    // MARK: - Layout Setup

    private func setupContainerViews() {
        dividerView.backgroundColor = .separator
        dividerView.translatesAutoresizingMaskIntoConstraints = false

        leftContainerView.translatesAutoresizingMaskIntoConstraints = false
        rightContainerView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(leftContainerView)
        view.addSubview(dividerView)
        view.addSubview(rightContainerView)

        NSLayoutConstraint.activate([
            // 左侧
            leftContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            leftContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftContainerView.widthAnchor.constraint(equalToConstant: leftWidth),

            // 分割线
            dividerView.topAnchor.constraint(equalTo: view.topAnchor),
            dividerView.leadingAnchor.constraint(equalTo: leftContainerView.trailingAnchor),
            dividerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dividerView.widthAnchor.constraint(equalToConstant: dividerWidth),

            // 右侧
            rightContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            rightContainerView.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor),
            rightContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Left Side: TabBarController with 2 tabs

    private func setupLeftSide() {
        let tabBar = UITabBarController()

        // Tab 1: Tech 文章列表
        let techListVC = ArticleListViewController(articles: DataStore.techArticles, title: "Tech")
        techListVC.onArticleSelected = { [weak self] article in
            self?.handleArticleSelected(article)
        }
        let techNav = UINavigationController(rootViewController: techListVC)
        techNav.tabBarItem = UITabBarItem(title: "Tech", image: UIImage(systemName: "laptopcomputer"), tag: 0)

        // Tab 2: News 文章列表
        let newsListVC = ArticleListViewController(articles: DataStore.newsArticles, title: "News")
        newsListVC.onArticleSelected = { [weak self] article in
            self?.handleArticleSelected(article)
        }
        let newsNav = UINavigationController(rootViewController: newsListVC)
        newsNav.tabBarItem = UITabBarItem(title: "News", image: UIImage(systemName: "newspaper"), tag: 1)

        tabBar.viewControllers = [techNav, newsNav]
        leftTabBarController = tabBar

        // addChild 添加到左侧容器
        addChild(tabBar)
        tabBar.view.translatesAutoresizingMaskIntoConstraints = false
        leftContainerView.addSubview(tabBar.view)
        NSLayoutConstraint.activate([
            tabBar.view.topAnchor.constraint(equalTo: leftContainerView.topAnchor),
            tabBar.view.leadingAnchor.constraint(equalTo: leftContainerView.leadingAnchor),
            tabBar.view.trailingAnchor.constraint(equalTo: leftContainerView.trailingAnchor),
            tabBar.view.bottomAnchor.constraint(equalTo: leftContainerView.bottomAnchor)
        ])
        tabBar.didMove(toParent: self)
    }

    // MARK: - Right Side: DetailViewController

    private func setupRightSide() {
        let detail = DetailViewController()
        detail.onOpenNewTab = { [weak self] article in
            self?.onOpenNewTab?(article)
        }
        detail.onOpenNewWindow = { [weak self] article in
            self?.onOpenNewWindow?(article)
        }
        detailVC = detail

        addChild(detail)
        detail.view.translatesAutoresizingMaskIntoConstraints = false
        rightContainerView.addSubview(detail.view)
        NSLayoutConstraint.activate([
            detail.view.topAnchor.constraint(equalTo: rightContainerView.topAnchor),
            detail.view.leadingAnchor.constraint(equalTo: rightContainerView.leadingAnchor),
            detail.view.trailingAnchor.constraint(equalTo: rightContainerView.trailingAnchor),
            detail.view.bottomAnchor.constraint(equalTo: rightContainerView.bottomAnchor)
        ])
        detail.didMove(toParent: self)
    }

    // MARK: - Article Selection Handler

    private func handleArticleSelected(_ article: Article) {
        detailVC.configure(with: article)
        // 通知 BrowserTabManager 更新 tab 标题
        if let manager = findBrowserTabManager() {
            manager.updateActiveTabTitle(article.title)
        }
    }

    /// 从外部（新 Tab 打开时）直接设置详情
    func showDetail(article: Article) {
        detailVC?.configure(with: article)
    }

    private func findBrowserTabManager() -> BrowserTabManagerViewController? {
        var p = parent
        while p != nil {
            if let mgr = p as? BrowserTabManagerViewController { return mgr }
            p = p?.parent
        }
        return nil
    }
}
