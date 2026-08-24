//
//  AppDelegate.swift
//  MultiTabController
//
//  Created by pan on 2026/8/20.
//

import UIKit

// @main 标记应用入口。
// 本工程刻意不使用 UISceneDelegate（无 Scene 生命周期），
// 因此在 AppDelegate 里手动创建 UIWindow，并把根控制器设为窗口根。
//
// 说明：ArticleListViewController / DetailViewController / DataStore 都是"示例 / Demo"代码，
// 已从库源码中拆出，放在与 AppDelegate 平级的宿主层；库本体不依赖它们。
// 其中 DetailViewController 是 PPContentDisplaying 的参考实现——库只认这个协议，
// 不含任何内容 UI，Tab 里显示什么由下面的 contentViewControllerProvider 决定。
@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // 必须持有 window：系统在启动完成后会通过 KVC 把窗口赋值到这里
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // 1. 创建窗口（传统生命周期，由我们自行管理）
        window = UIWindow(frame: UIScreen.main.bounds)

        // 2. iPhone 根：两个列表包进标签栏，点内容 push 详情。
        let iPhoneRoot: () -> UIViewController = {
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

        // 3. iPad / Mac 根：左侧列表 + 右侧多 Tab 详情宿主。
        let iPadOrMacRoot: () -> UIViewController = {
            let router = PPSplitContentRouter()
            let categories: [(title: String, image: UIImage?, items: [PPContentItem])] = [
                ("Tech", UIImage(systemName: "cpu"), DataStore.techArticles),
                ("News", UIImage(systemName: "newspaper"), DataStore.newsArticles)
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

        // 4. 由 RootBuilder 根据设备分发到上面两套根之一。
        window?.rootViewController = RootBuilder.makeRoot(
            iPhoneRoot: iPhoneRoot,
            iPadOrMacRoot: iPadOrMacRoot
        )

        // 5. 让窗口成为主窗口并显示出来
        window?.makeKeyAndVisible()

        return true
    }
}
