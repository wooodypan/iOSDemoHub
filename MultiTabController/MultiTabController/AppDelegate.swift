import UIKit

// @main 标记应用入口。
//
// 本工程**同时兼容两套生命周期**，由 Info.plist 决定当前走哪一套：
//
//   1) UIScene 生命周期（当前启用；iOS 27 SDK 起 Apple 强制要求，见 TN3187）
//      Info.plist 里配了 UIApplicationSceneManifest → 窗口由 SceneDelegate 创建，
//      本类的 didFinishLaunchingWithOptions 只管进程级的事。
//   2) 传统 AppDelegate 生命周期
//      把 Info.plist 里的 UIApplicationSceneManifest 整块删掉，UIKit 就退回老模式，
//      窗口必须由本类创建 —— 就是下面那段被 if 挡住的代码。
//
// 两套路线共用 DemoRootFactory 里的根构建代码，所以业务 UI 一行都不用改。
// 运行期想知道当前是哪一套，读库里的 `AppLifecycle.usesSceneLifecycle` 即可。
//
// 说明：DemoRootFactory / ArticleListViewController / DetailViewController / DataStore
// 都是“示例 / Demo”代码，位于与 AppDelegate 平级的宿主层；库本体不依赖它们。
// 其中 DetailViewController 是 PPContentDisplaying 的参考实现——库只认这个协议，
// 不含任何内容 UI，Tab 里显示什么由 DemoRootFactory 决定。
@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // 窗口只在「传统生命周期」下归本类所有（Scene 生命周期下窗口属于 SceneDelegate）。
    // 系统启动完成后也会通过 KVC 把窗口赋值到这里，所以这个属性必须保留。
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // 进程级的逻辑放这里（启动上报、解压、注册推送、检查更新…），
        // 它在两种生命周期下都会被调用，不受 Scene 迁移影响。
        //
        // 注意：这里不要碰 self.window —— Scene 生命周期下此刻场景还没建立，窗口必然是 nil。

        // 传统生命周期兜底：只有 App 没采用 UIScene 时才需要本类建窗口。
        // 判据直接用库里的 AppLifecycle（口径与 TN3187 一致：配了场景清单就是 Scene 模式）。
        if !AppLifecycle.usesSceneLifecycle {
            let window = RootBuilder.makeWindow(
                iPhoneRoot: { DemoRootFactory.makeiPhoneRoot() },
                iPadOrMacRoot: { DemoRootFactory.makeiPadOrMacRoot() }
            )
            self.window = window
            window.makeKeyAndVisible()
        }

        return true
    }
}
