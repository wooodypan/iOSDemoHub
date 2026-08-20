import UIKit

// MARK: - CustomSplitViewController
// 用 addChild 手动实现左右分屏：
//   左侧：UITabBarController（内含2个 NavigationController+ListVC）
//   右侧：DetailViewController
// 本控制器不再自己处理“选中文章”的业务逻辑，而是把事件转发给 BrowserTabManagerViewController：
//   - onArticlePreviewSelected：左侧列表“单击”（预览）
//   - onArticleOpenSelected：左侧列表“双击”（正式打开）
//   - onTabPinned：右侧详情被编辑（输入备注）时，把当前 Tab 固定为正式 Tab
class CustomSplitViewController: UIViewController {

    // 回调：通知父容器（BrowserTabManager）
    var onArticlePreviewSelected: ((Article) -> Void)?   // 单击：预览
    var onArticleOpenSelected: ((Article) -> Void)?      // 双击：正式打开
    var onOpenNewTab: ((Article) -> Void)?
    var onOpenNewWindow: ((Article) -> Void)?
    // 详情被编辑时回调：true=已编辑（固定为正式Tab），false=已清空
    var onTabPinned: ((Bool) -> Void)?

    // 关键 Bool 属性：当前这个分屏（Tab）是否已被“固定”。
    // 当右侧详情输入框输入文字时会被设为 true；清空则变回 false。
    var isPinned: Bool = false

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
        // 单击 -> 预览；双击 -> 正式打开（转发给父容器 BrowserTabManager 决定如何建 Tab）
        techListVC.onArticleSelected = { [weak self] article in
            self?.onArticlePreviewSelected?(article)
        }
        techListVC.onArticleDoubleSelected = { [weak self] article in
            self?.onArticleOpenSelected?(article)
        }
        let techNav = UINavigationController(rootViewController: techListVC)
        techNav.tabBarItem = UITabBarItem(title: "Tech", image: UIImage(systemName: "laptopcomputer"), tag: 0)

        // Tab 2: News 文章列表
        let newsListVC = ArticleListViewController(articles: DataStore.newsArticles, title: "News")
        newsListVC.onArticleSelected = { [weak self] article in
            self?.onArticlePreviewSelected?(article)
        }
        newsListVC.onArticleDoubleSelected = { [weak self] article in
            self?.onArticleOpenSelected?(article)
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
        // 详情备注框被编辑时：更新本分屏的 isPinned，并通知父容器固定当前 Tab
        detail.onEditStateChanged = { [weak self] hasText in
            self?.isPinned = hasText
            self?.onTabPinned?(hasText)
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

    /// 从外部（新 Tab 打开时）直接设置详情
    func showDetail(article: Article) {
        detailVC?.configure(with: article)
    }
}
