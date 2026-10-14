import UIKit

// MARK: - DemoRootFactory
// 宿主层（与 AppDelegate 平级，**不随 pod / SPM 发布**）：Demo 的「根界面」怎么搭。
//
// 单独抽成一个文件，是为了让两套生命周期共用同一份根构建代码：
//   - Scene 生命周期：SceneDelegate.scene(_:willConnectTo:session:options:) 调它；
//   - 传统生命周期：AppDelegate.application(_:didFinishLaunchingWithOptions:) 调它。
// 以后在两种生命周期之间切换，这个文件一行都不用改。
//
// 其中 ArticleListViewController / DetailViewController / DataStore 都是"示例 / Demo"代码，
// 库本体不依赖它们：库只认 PPContentDisplaying 协议，不含任何内容 UI，
// Tab 里显示什么完全由下面的 contentViewControllerProvider 决定。
enum DemoRootFactory {

    /// iPhone 根：两个列表包进标签栏，点内容 push 详情。
    static func makeiPhoneRoot() -> UIViewController {
        let techList = ArticleListViewController(articles: DataStore.techArticles, title: "Tech")
        let newsList = ArticleListViewController(articles: DataStore.newsArticles, title: "News")
        let techNav = UINavigationController(rootViewController: techList)
        let newsNav = UINavigationController(rootViewController: newsList)

        // 内容页工厂：库不含内容 UI，这里注入宿主自己的 DetailViewController。
        techList.router = PPPhoneContentRouter(
            sourceViewController: techList,
            contentViewControllerProvider: { DetailViewController() }
        )
        newsList.router = PPPhoneContentRouter(
            sourceViewController: newsList,
            contentViewControllerProvider: { DetailViewController() }
        )

        return TabBarBuilder.build(viewControllers: [techNav, newsNav], titles: ["Tech", "News"])
    }

    /// iPad / Mac 根：左侧列表 + 右侧多 Tab 详情宿主。
    static func makeiPadOrMacRoot() -> UIViewController {
        let router = PPSplitContentRouter()

        // SF Symbols 是 iOS 13+ 才有的能力，而本工程最低支持 iOS 12，
        // 所以低版本回退成 nil（图标在这个 Demo 里本来就没用到）。
        func symbolImage(named name: String) -> UIImage? {
            if #available(iOS 13.0, *) {
                return UIImage(systemName: name)
            }
            return nil
        }

        let categories: [(title: String, image: UIImage?, items: [PPContentItem])] = [
            ("Tech", symbolImage(named: "cpu"), DataStore.techArticles),
            ("News", symbolImage(named: "newspaper"), DataStore.newsArticles)
        ]
        let lists = categories.map { title, _, items -> UIViewController in
            let list = ArticleListViewController(articles: items, title: title)
            list.router = router
            return list
        }
        // 用 PPTabItem 传入图标，演示 TabBarBuilder 新开放的图标能力。
        let sidebar = TabBarBuilder.build(
            viewControllers: lists,
            items: categories.map { PPTabItem(title: $0.title, image: $0.image) }
        )
        return SplitContainerViewController(
            leftViewController: sidebar,
            router: router,
            contentViewControllerProvider: { DetailViewController() }
        )
    }
}
