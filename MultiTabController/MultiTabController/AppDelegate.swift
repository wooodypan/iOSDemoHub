//
//  AppDelegate.swift
//  MultiTabController
//
//  Created by pan on 2026/8/20.
//

import UIKit

// @main 标记应用入口。
// 本工程刻意不使用 UISceneDelegate（无 Scene 生命周期），
// 因此在 AppDelegate 里手动创建 UIWindow，并把 RootContainerViewController 设为根控制器。
@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // 必须持有 window：系统在启动完成后会通过 KVC 把窗口赋值到这里
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // 1. 创建窗口（传统生命周期，由我们自行管理）
        window = UIWindow(frame: UIScreen.main.bounds)

        // 2. 把 RootContainerViewController 作为根控制器。
        //    RootContainerViewController 内部会根据设备类型（iPhone / iPad / Mac）
        //    自动选择“TabBar 布局”或“可新建多 Tab 的分屏浏览器布局”。
        let techListVC = ArticleListViewController(articles: DataStore.techArticles, title: "Tech")
        let techNav = UINavigationController(rootViewController: techListVC)

        let newsListVC = ArticleListViewController(articles: DataStore.newsArticles, title: "News")
        let newsNav = UINavigationController(rootViewController: newsListVC)
        window?.rootViewController = RootContainerViewController(viewControllers: [techNav,newsNav], titles: ["Tech","News"])

        // 3. 让窗口成为主窗口并显示出来
        window?.makeKeyAndVisible()

        return true
    }
}
