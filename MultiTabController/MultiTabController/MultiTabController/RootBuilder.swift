import UIKit

// MARK: - RootBuilder
// 应用“根控制器”的工厂：把“按设备选择布局”的逻辑从 AppDelegate 里抽出来。
// 直接产出最终要当作 window.rootViewController 的控制器，
// 不再包一层“不显示任何内容的纯路由容器 VC”。
enum RootBuilder {

    /// 根据当前设备类型，直接产出根控制器：
    ///   - iPhone：用 TabBarBuilder 构造 “Tech / News” 标签栏（列表包在导航控制器里，便于 push 详情）。
    ///   - iPad / Mac：直接返回类浏览器的多 Tab 分屏管理器 BrowserTabManagerViewController。
    static func makeRoot() -> UIViewController {
        switch DeviceHelper.currentLayout {
        case .iPadOrMac:
            // iPad / Mac 走“可新建多 Tab 的分屏浏览器”，它自身就是完整页面，直接当 root。
            return BrowserTabManagerViewController()

        case .iPhone:
            // 构造默认的两个列表（包一层导航控制器，保证 iPhone 上点文章能 push 到详情页）。
            let techNav = UINavigationController(
                rootViewController: ArticleListViewController(articles: DataStore.techArticles, title: "Tech")
            )
            let newsNav = UINavigationController(
                rootViewController: ArticleListViewController(articles: DataStore.newsArticles, title: "News")
            )
            // 复用 TabBarBuilder 把数组+标题变成标准 PPTabBarController。
            return TabBarBuilder.build(viewControllers: [techNav, newsNav], titles: ["Tech", "News"])
        }
    }
}
