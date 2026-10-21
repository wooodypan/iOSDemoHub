import UIKit

// MARK: - PPAppearanceMode
//
// 手动外观模式：让用户在 App 里自己选浅色 / 深色，而不是只能跟着系统设置走。
// 用 Int 当原始值是有意的 —— 要写进 UserDefaults，整数比字符串更不容易写错、也不会因为本地化变化而失效。
public enum PPAppearanceMode: Int, CaseIterable {

    /// 跟随系统（默认值）。等价于"我不覆盖，听系统的"。
    case system = 0
    /// 强制浅色，系统切到深色也不受影响。
    case light = 1
    /// 强制深色，系统切到浅色也不受影响。
    case dark = 2

    /// 转成 UIKit 的界面样式。`.system` 对应 `.unspecified`，这是 UIKit 里表示"不覆盖"的取值。
    @available(iOS 13.0, *)
    public var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// 给界面直接用的默认文案。外部如果有自己的多语言方案，忽略它自己映射即可。
    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

// MARK: - PPAppearance
//
// 全局外观开关。目标是「外部一行代码接入」：
//
//     PPAppearance.mode = .dark        // 立刻变深色
//     PPAppearance.mode = .system      // 交还给系统
//
// 实现方式是在 UIWindow 上设 overrideUserInterfaceStyle。
// 为什么设在 window 而不是每个 ViewController 上？
//   window 是 trait 的源头，覆盖一处就能让整棵视图树（包括之后 push / present 出来的页面）都跟着变，
//   不用逐个页面处理，也不会漏掉运行期才创建的子页面。
//
// iOS 12 没有深色模式（UIUserInterfaceStyle 这个类型本身就是 iOS 13 才有的），
// 所以这个开关在 iOS 12 上不产生任何效果，页面保持浅色 —— 与库原本的深色回退策略一致。
// 想在 iOS 12 上隐藏入口，用 if #available(iOS 13.0, *) 判一下即可。
@MainActor
public enum PPAppearance {

    // MARK: - 当前模式

    /// 当前外观模式，赋值立刻生效。
    ///
    /// 赋值后依次做三件事：写 UserDefaults（如果开了持久化）、给所有窗口设覆盖样式、广播 `.ppAppearanceDidChange`。
    /// - Note: 新旧值相同时直接返回，不会重复写盘、也不会重复发通知。
    public static var mode: PPAppearanceMode = .system {
        didSet {
            guard mode != oldValue else { return }
            persistCurrentMode()
            applyToAllWindows()
            NotificationCenter.default.post(name: .ppAppearanceDidChange, object: nil)
        }
    }

    // MARK: - 持久化

    /// 保存模式用的 UserDefaults 键。设成 nil 就彻底关掉持久化（纯内存，重启回到 `.system`）。
    ///
    /// 默认给了一个值，因为绝大多数 App 都希望"用户选过之后记住"。
    /// 如果你的 App 有自己的配置中心 / 远程配置，把它设成 nil，然后在启动时自己给 `mode` 赋值。
    /// - Important: 要在调用 `restore()` 之前设置，否则读写用的还是旧键。
    public static var persistenceKey: String? = "PPAppearanceMode"

    /// 读回上次保存的模式并应用。启动时调一次即可，位置在建窗口之前（见 README 的接入示例）。
    ///
    /// 没存过值、或存的值不合法（比如降级后枚举没这一项）时什么都不做，
    /// `mode` 保持当前值（默认 `.system`），不会因为脏数据把界面搞坏。
    public static func restore() {
        guard let key = persistenceKey,
              let raw = UserDefaults.standard.object(forKey: key) as? Int,
              let saved = PPAppearanceMode(rawValue: raw) else { return }
        mode = saved
    }

    /// 清掉持久化的值并回到跟随系统。给"恢复默认设置"这类入口用。
    public static func reset() {
        if let key = persistenceKey {
            UserDefaults.standard.removeObject(forKey: key)
        }
        mode = .system
    }

    // 写盘。持久化关掉时什么也不做。
    private static func persistCurrentMode() {
        guard let key = persistenceKey else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: key)
    }

    // MARK: - 应用

    /// 把当前模式套到指定窗口上。
    ///
    /// 用 `RootBuilder.makeWindow` 建窗口的话，库内部已经调过了，不用自己调；
    /// 自己 new UIWindow 的宿主，在建完窗口后补一次即可。
    public static func apply(to window: UIWindow) {
        guard #available(iOS 13.0, *) else { return }
        window.overrideUserInterfaceStyle = mode.userInterfaceStyle
    }

    /// 把当前模式套到所有窗口上（多窗口 App 也能一起覆盖）。
    ///
    /// `mode` 的 setter 会自动调它，平时不用手动调。
    /// 只有当窗口是后来才出现的时候（例如自己用 requestSceneSessionActivation 开新场景）需要补一次，
    /// 否则新窗口会退回跟随系统，看起来像是"切换只在旧窗口生效"。
    public static func applyToAllWindows() {
        guard #available(iOS 13.0, *) else { return }
        for window in allWindows() {
            window.overrideUserInterfaceStyle = mode.userInterfaceStyle
        }
    }

    // 收集当前 App 的所有窗口：先按场景走（Scene 生命周期），再补上 AppDelegate.window（传统生命周期）。
    // 两条路可能拿到同一个窗口，所以末尾用 ObjectIdentifier 去重，避免同一个窗口被设两遍。
    private static func allWindows() -> [UIWindow] {
        var windows: [UIWindow] = []

        if #available(iOS 13.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                windows.append(contentsOf: windowScene.windows)
            }
        }

        // 传统生命周期下窗口不在场景里，只能从 AppDelegate 取；
        // delegate.window 本身是可选属性，所以这里要展平一层。
        if let delegate = UIApplication.shared.delegate, let window = delegate.window ?? nil {
            windows.append(window)
        }

        var seen = Set<ObjectIdentifier>()
        return windows.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
}

// MARK: - 通知
public extension Notification.Name {

    /// 手动切换外观后发出（`object` 为 nil）。
    ///
    /// 用来处理那些不会自动跟着 trait 变化的东西，最典型的就是 `CALayer.borderColor` 和 `shadowColor`
    /// 这类 CGColor —— 它们不参与动态色解析，必须在回调里用 resolvedColor(with:) 重新算一遍再赋回去。
    /// 常规的 backgroundColor / textColor 用动态色就够了，不需要监听这个通知。
    static let ppAppearanceDidChange = Notification.Name("PPAppearanceDidChange")
}
