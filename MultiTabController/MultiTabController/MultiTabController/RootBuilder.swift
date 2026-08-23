import UIKit

// MARK: - RootBuilder
// 应用“根控制器”的工厂：把“按设备选择布局”的逻辑从 AppDelegate 里抽出来。
// 直接产出最终要当作 window.rootViewController 的控制器，
// 不再包一层“不显示任何内容的纯路由容器 VC”。
enum RootBuilder {

    /// 根据当前设备类型，直接产出根控制器：
    ///   - iPhone：用 TabBarBuilder 构造 “Tech / News” 标签栏（列表包在导航控制器里，便于 push 详情）。
    ///   - iPad / Mac：直接返回分栏根控制器 SplitContainerViewController（左列表 + 右多 Tab 详情宿主）。
    static func makeRoot() -> UIViewController {
        switch DeviceHelper.currentLayout {
        case .iPadOrMac:
            // iPad / Mac 走分栏：左列表 + 右 DetailHostViewController（浏览器式多 Tab 详情宿主）。
            return SplitContainerViewController()

        case .iPhone:
            // 构造默认的两个列表（包一层导航控制器，保证 iPhone 上点文章能 push 到详情页）。
            let techList = ArticleListViewController(articles: DataStore.techArticles, title: "Tech")
            let newsList = ArticleListViewController(articles: DataStore.newsArticles, title: "News")
            let techNav = UINavigationController(rootViewController: techList)
            let newsNav = UINavigationController(rootViewController: newsList)

            // 给列表装上 iPhone 路由：单击/双击都 push 详情，新窗口走 WindowManager。
            techList.router = PhoneArticleRouter(sourceViewController: techList)
            newsList.router = PhoneArticleRouter(sourceViewController: newsList)

            // 复用 TabBarBuilder 把数组+标题变成标准 PPTabBarController。
            return TabBarBuilder.build(viewControllers: [techNav, newsNav], titles: ["Tech", "News"])
        }
    }
}
