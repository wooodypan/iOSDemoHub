import UIKit

// MARK: - RootBuilder
// 应用“根控制器”的工厂：按设备选择布局。
// 具体的左侧列表 / 示例数据由调用方（宿主 App）通过闭包注入，
// 本工厂只负责“按设备返回对应根控制器 / 窗口”，不感知任何业务内容（保持库纯净）。
public enum RootBuilder {

    // MARK: - 根控制器

    /// 根据当前设备类型，返回对应的根控制器：
    ///   - iPhone：调用 iPhoneRoot 构建（通常是 PPTabBarController 包着若干列表）；
    ///   - iPad / Mac：调用 iPadOrMacRoot 构建（通常是 SplitContainerViewController）。
    /// 两个闭包均由调用方提供，库本身不包含任何示例列表或数据。
    public static func makeRoot(
        iPhoneRoot: @escaping () -> UIViewController,
        iPadOrMacRoot: @escaping () -> UIViewController
    ) -> UIViewController {
        switch DeviceHelper.currentLayout {
        case .iPhone:
            return iPhoneRoot()
        case .iPadOrMac:
            return iPadOrMacRoot()
        }
    }

    // MARK: - 窗口（两套生命周期各一个重载，业务代码不用改）

    /// **UIScene 生命周期**用这个重载：在 SceneDelegate 的
    /// `scene(_:willConnectTo:session:options:)` 里把 windowScene 传进来。
    ///
    /// - Important: 窗口必须挂到场景上，否则它在屏幕上根本不显示，
    ///   而且 `isHidden` 还是 false —— 属于最难查的一类问题。
    /// - Returns: 建好的窗口（**不显示**，需要的话由调用方 `makeKeyAndVisible()`）。
    @available(iOS 13.0, *)
    public static func makeWindow(
        windowScene: UIWindowScene,
        iPhoneRoot: @escaping () -> UIViewController,
        iPadOrMacRoot: @escaping () -> UIViewController
    ) -> UIWindow {
        // 挂在场景上的窗口：frame 由系统按场景大小安排好，不用也不该自己设。
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = makeRoot(iPhoneRoot: iPhoneRoot, iPadOrMacRoot: iPadOrMacRoot)
        return window
    }

    /// **传统 AppDelegate 生命周期**（以及 iOS 12）用这个重载：在
    /// `application(_:didFinishLaunchingWithOptions:)` 里直接调用即可，不需要 `#available` 包一层。
    ///
    /// - Returns: 建好的窗口（**不显示**，需要的话由调用方 `makeKeyAndVisible()`）。
    public static func makeWindow(
        iPhoneRoot: @escaping () -> UIViewController,
        iPadOrMacRoot: @escaping () -> UIViewController
    ) -> UIWindow {
        // 自己按屏幕尺寸建窗口。
        // 注意 UIWindow(frame:) 建出来的窗口不会挂到任何场景上，
        // 所以「Scene 生命周期」必须走上面那个重载，别用这一个。
        // UIScreen.main 从 iOS 26 起已废弃（官方建议从 view.window.windowScene.screen 取），
        // 但传统生命周期下压根没有场景可依，这里只能这么写；Scene 路线走不到这一支。
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = makeRoot(iPhoneRoot: iPhoneRoot, iPadOrMacRoot: iPadOrMacRoot)
        return window
    }
}
