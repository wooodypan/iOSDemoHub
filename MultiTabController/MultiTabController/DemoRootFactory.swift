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
        let lists: [ArticleListViewController] = categories.map { title, _, items in
            let list = ArticleListViewController(articles: items, title: title)
            list.router = router
            return list
        }

        // 用 PPTabItem 传入图标，演示 TabBarBuilder 新开放的图标能力。
        let sidebar = TabBarBuilder.build(
            viewControllers: lists,
            items: categories.map { PPTabItem(title: $0.title, image: $0.image) }
        )

        // 外观入口挂在外层导航栏上，不要再给每个列表包 UINavigationController ——
        // SplitContainerViewController 内部已经用一个 leftNavigationController 包住了整个侧栏，
        // 再包一层就会出现两条导航栏、两个标题叠在一起。
        sidebar.navigationItem.rightBarButtonItem = lists[0].makeAppearanceBarButtonItem()
        let split = SplitContainerViewController(
            leftViewController: sidebar,
            router: router,
            contentViewControllerProvider: { DetailViewController() }
        )

        // 右侧选中 Tab 变化 -> 同步左侧列表高亮（VS Code 资源管理器式联动）：
        //   1. 在所有列表里清掉旧高亮，再给“包含该内容”的那个列表高亮对应行；
        //   2. 如果这条内容属于另一个分类的列表，把左侧标签栏也切过去，
        //      这样右侧切到 News 的 Tab 时，左侧不会还停在 Tech 列表上。
        split.detailHost.onSelectedItemChanged = { [weak sidebar] item in
            for (index, list) in lists.enumerated() {
                if let item = item, list.containsItem(withID: item.id) {
                    list.setHighlightedItemID(item.id, scrollToSelection: true)
                    if sidebar?.selectedIndex != index {
                        sidebar?.selectIndex(index)
                    }
                } else {
                    list.setHighlightedItemID(nil)
                }
            }
        }
        return split
    }
}
