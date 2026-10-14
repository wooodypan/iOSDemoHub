import UIKit

// MARK: - AppLifecycleMode
// App 的启动 / 生命周期模型，只有这两种可能：
//
//   - appDelegate：传统生命周期。AppDelegate 在
//     application(_:didFinishLaunchingWithOptions:) 里自己 new 一个 UIWindow（iOS 12 时代的写法）。
//   - scene      ：UIScene 生命周期。窗口由 UISceneDelegate 在
//     scene(_:willConnectTo:options:) 里创建，AppDelegate 只管进程级的事。
//
// 为什么库要自己判断这件事？
//   库内部需要“找到当前该用的那个 UIWindow”（例如 WindowManager 弹新窗口时要挑一个控制器来 present），
//   而两种生命周期下窗口的归属完全不同：传统生命周期归 AppDelegate，Scene 生命周期归 UIWindowScene。
//   宿主用哪套是宿主的自由，库不能假设，所以这里做成运行时判断——同一份库代码，两种宿主都能跑。
public enum AppLifecycleMode {
    case appDelegate
    case scene
}

// MARK: - AppLifecycle
// 生命周期相关的运行时环境查询。全部是只读属性，不会写入任何状态。
//
// 注意：这些属性请在主线程读取（内部会访问 UIApplication.shared）。
public enum AppLifecycle {

    // MARK: - 生命周期判定

    /// 当前 App 采用的是哪套生命周期。
    ///
    /// 判定标准与 Apple 技术说明 TN3187 里「是否需要迁移到 Scene 生命周期」的两条判据完全一致，
    /// 满足任意一条就算已采用 UIScene 生命周期：
    ///   1. Info.plist 里有 UIApplicationSceneManifest，且里面的 UISceneConfigurations 不为空；
    ///   2. AppDelegate 实现了 application(_:configurationForConnecting:options:)。
    public static var mode: AppLifecycleMode {
        // iOS 12 及以下压根没有 UIScene 这一套，必然是传统生命周期。
        guard #available(iOS 13.0, *) else { return .appDelegate }

        return hasSceneConfiguration ? .scene : .appDelegate
    }

    /// 便捷写法：当前 App 是否已采用 UIScene 生命周期。
    /// 常用于「窗口该由谁创建」的判断，见 RootBuilder.makeWindow(windowScene:…) 的注释。
    public static var usesSceneLifecycle: Bool {
        return mode == .scene
    }

    // TN3187 的两条判据，任意一条成立即视为「已采用」。
    private static var hasSceneConfiguration: Bool {
        // 判据 1：Info.plist 里配了场景清单，并且场景配置不是空的。
        // 注意「空配置」不算：只写个 UIApplicationSceneManifest、UISceneConfigurations 里什么都没有，
        // UIKit 根本建不出场景，等于没配（Apple 文档里明确把这种情况归到「需要迁移」）。
        if let manifest = Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any],
           let configurations = manifest["UISceneConfigurations"] as? [String: Any],
           configurations.isEmpty == false {
            return true
        }

        // 判据 2：AppDelegate 用代码返回场景配置。
        // 这条路线可以完全不写 Info.plist，所以必须单独探测：拿 ObjC 选择器名问一句“你实现了吗”。
        // （application(_:configurationForConnecting:options:) 编译后的选择器名就是这个字符串。）
        let selector = NSSelectorFromString("application:configurationForConnectingSceneSession:options:")
        if let delegate = UIApplication.shared.delegate, delegate.responds(to: selector) {
            return true
        }

        return false
    }

    // MARK: - 窗口查询

    /// 当前正在使用的窗口场景（UIWindowScene）。
    /// 传统生命周期下没有场景，返回 nil；Mac Catalyst 下必然有场景。
    /// 标注 iOS 13 起可用：UIWindowScene 这个类型本身就是 iOS 13 才有的，
    /// 所以整个属性在 iOS 12 上不可见（那种情况请直接用 activeWindow）。
    @available(iOS 13.0, *)
    public static var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        // 优先「前台活跃」的那个场景：支持多窗口时，就是用户正在用的那一个。
        if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return active
        }
        // 退一步：还没进前台时（例如冷启动 willConnectTo 阶段）场景是 inactive 状态。
        if let inactive = scenes.first(where: { $0.activationState == .foregroundInactive }) {
            return inactive
        }
        // 兜底：拿第一个窗口场景。
        return scenes.first
    }

    /// 当前「界面应该往哪儿放」的那个窗口。
    ///
    /// - Scene 生命周期：取自窗口场景（UIWindowScene）。
    /// - 传统生命周期：取自 AppDelegate 的 window 属性。
    ///
    /// 两条路都走通了，库内部的窗口相关逻辑就不必再按平台 / 生命周期分叉。
    public static var activeWindow: UIWindow? {
        // 先走场景：Scene 生命周期、Mac Catalyst 都靠这一条。
        if #available(iOS 13.0, *), let windowScene = activeWindowScene {
            // UIWindowScene.keyWindow 是 iOS 15 才有的；低版本自己从 windows 里挑
            // （isKeyWindow 从 iOS 2 就有，所以这条兜底对所有版本都成立）。
            if #available(iOS 15.0, *), let key = windowScene.keyWindow {
                return key
            }
            // 挑「正在接收键盘事件」的那个；窗口刚建好、还没轮到它时退一步取第一个，
            // 避免在 makeKeyAndVisible 之前拿到 nil。
            return windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
        }

        // 再走传统生命周期：用 UIApplicationDelegate.window。
        // 不用 UIApplication.shared.keyWindow，原因是它从 iOS 13 起就废弃了，
        // 而且多场景下它返回的是「所有场景里」的 keyWindow，语义并不对。
        return UIApplication.shared.delegate?.window ?? nil
    }

    /// 当前 App 是否具备「开真正的多窗口」的条件。
    ///
    /// 需要同时满足：Scene 生命周期 + Info.plist 里 UIApplicationSupportsMultipleScenes = YES。
    /// 传统生命周期、或没开多窗口的 App 都是 false，这时「新窗口」只能降级成模态弹出
    /// （见 WindowManager.openNewWindow 的说明）。
    public static var supportsMultipleScenes: Bool {
        guard #available(iOS 13.0, *) else { return false }
        return UIApplication.shared.supportsMultipleScenes
    }
}
