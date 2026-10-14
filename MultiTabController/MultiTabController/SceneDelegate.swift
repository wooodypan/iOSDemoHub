import UIKit

// MARK: - SceneDelegate
// UIScene 生命周期下的「窗口管理员」。
//
// 为什么需要它？（Apple TN3187）
//   用 iOS 27 SDK 构建的 App 必须采用 UIScene 生命周期，否则一启动就断言失败：
//   "UIScene life cycle is required for apps built with this SDK."
//   判定标准是下面两条，满足任意一条即算“已采用”：
//     1. Info.plist 里有 UIApplicationSceneManifest，且 UISceneConfigurations 不为空；
//     2. AppDelegate 实现了 application(_:configurationForConnecting:options:)。
//   本工程走的是第 1 条（见 MultiTabController/Info.plist 里的 UIApplicationSceneManifest，
//   UISceneDelegateClassName = $(PRODUCT_MODULE_NAME).SceneDelegate 就是下面这个类）。
//
// 窗口的归属变了：
//   传统生命周期里窗口是 AppDelegate 的（self.window）；采用 Scene 之后，
//   每个场景各有一个窗口，归这个 UISceneDelegate 所有。
//
// ⚠️ 迁移时最容易漏的一点：一旦采用 Scene 生命周期，UIKit 就**不再调用** AppDelegate 里那些
//   界面相关的回调（applicationDidBecomeActive / WillResignActive / DidEnterBackground /
//   WillEnterForeground / application:openURL:options: …），哪怕实现还留在那里也不调用。
//   本 Demo 没有这类逻辑，所以只实现了建窗口；你的 App 如果有，要搬到下面这些
//   sceneDidBecomeActive / sceneWillResignActive / sceneDidEnterBackground 里。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    // 系统约定：场景的主窗口用 window 这个名字，UIKit 会通过 KVC 认领它，
    // 所以属性名不能改，而且要强持有（否则窗口会随对象释放一起消失）。
    var window: UIWindow?

    // 场景建立时调用一次：这一步等价于传统生命周期里「在 didFinishLaunching 里建窗口」。
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // 只处理窗口场景（UIWindowScene）；CarPlay 之类的其它场景类型不在这里管。
        guard let windowScene = scene as? UIWindowScene else { return }

        // 窗口 + 根控制器：跟传统生命周期共用库里的同一个入口，
        // 区别只是这里必须把 windowScene 传进去——不挂到场景上的窗口在屏幕上不显示。
        let window = RootBuilder.makeWindow(
            windowScene: windowScene,
            iPhoneRoot: { DemoRootFactory.makeiPhoneRoot() },
            iPadOrMacRoot: { DemoRootFactory.makeiPadOrMacRoot() }
        )

        // 先存起来再显示：UIKit 需要能通过 self.window 找到这个场景的窗口。
        self.window = window
        window.makeKeyAndVisible()

        // 冷启动参数也搬家了：传统生命周期从 launchOptions 里读的东西，
        // 现在要从 connectionOptions 里读，例如：
        //   connectionOptions.urlContexts       → 启动时带来的 URL（scene:openURLContexts: 也会收到）
        //   connectionOptions.userActivities   → 启动时带来的 Handoff / 快捷指令
        //   connectionOptions.notificationResponse → 点推送冷启动
        // 本 Demo 用不到，所以留空。
    }

    // MARK: - 场景生命周期回调（用到哪个补哪个，这里只做示例性说明）

    // 场景断开连接（用户关掉窗口 / 系统回收）：等价于老生命周期的 applicationWillTerminate，
    // 适合在这里做“保存状态、断开连接”。
    func sceneDidDisconnect(_ scene: UIScene) {}

    // 场景进入活跃状态：等价于 applicationDidBecomeActive。
    func sceneDidBecomeActive(_ scene: UIScene) {}

    // 场景即将失去活跃（例如上滑悬停、来了系统弹窗）：等价于 applicationWillResignActive，
    // 适合在这里提交 H5 进度、暂停动画。
    func sceneWillResignActive(_ scene: UIScene) {}

    // 场景即将进入前台：等价于 applicationWillEnterForeground。
    // 注意冷启动时它也会走一次（顺序：willConnectTo → sceneWillEnterForeground → sceneDidBecomeActive），
    // 搬过来的逻辑要确认幂等。
    func sceneWillEnterForeground(_ scene: UIScene) {}

    // 场景已进入后台：等价于 applicationDidEnterBackground，适合在这里保存数据、停掉定时任务。
    func sceneDidEnterBackground(_ scene: UIScene) {}
}
