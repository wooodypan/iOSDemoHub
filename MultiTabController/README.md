# MultiTabController

一套可复用的 iOS UI 组件，用于构建「左侧分类列表 + 右侧多 Tab 详情宿主」的分栏界面，
并实现了类似 VS Code 的 Tab 复用策略（预览 / 正式 / 固定）。已适配 **iPhone、iPad 与 Mac Catalyst**。

## 功能特性

- **RootBuilder**：按设备自动选择布局（调用方传入 iPhone 根 / iPad·Mac 根两个闭包）
  - iPhone → 标签栏（列表，点内容 push 详情）
  - iPad / Mac → 分栏根控制器 `SplitContainerViewController`（左栏由调用方注入 + 右 `DetailHostViewController` 多 Tab 详情宿主）
- **SplitContainerViewController**：iPad / Mac 的根控制器，左栏由调用方注入，右栏为多 Tab 详情宿主；通过 `PPSplitContentRouter` 把「打开内容」意图转交右侧
- **PPContentItem**：库的内容模型（id / title / body / category），集成方用自身业务模型映射成它即可驱动本库
- **PPContentRouting / PPContentOpenMode**：协议化路由，把「列表点开内容」的意图与具体设备环境解耦（Phone 走导航栈 push，Split 走右侧多 Tab 宿主）
- **ArticleListViewController**：示例列表页，用单击（预览）/ 双击（正式）手势对应 VS Code Tab 策略（属 Demo，不随库发布）
- **DetailViewController**：右侧详情页，含「标记为已编辑 / 清除编辑标记」示例，用于固定当前 Tab
- **DetailHostViewController**：右侧多 Tab 宿主，承载 VS Code 预览/正式语义
- **按内容 ID 去重**：`DetailHostViewController.deduplicateOpenedItems`（默认 `true`）。打开一个**已经打开过**的内容时不再新建 Tab，而是直接定位到那个 Tab；置 `false` 则恢复原语义（同一个内容可以开成多个 Tab）。比较依据是 `PPContentItem.id`，所以请保证业务 id 在同一个宿主里唯一；没有内容的空 Tab 不参与去重
- **Tab 条外观可定制**：Tab 单元格只圆**上面两个角**、底边与 Tab 条底边对齐、顶部留 5pt 间距（像浏览器标签页一样「从底边长出来」）；选中 / 未选中底色由 `DetailHostViewController.tabSelectedBackgroundColor` / `.tabUnselectedBackgroundColor` 两个公开变量控制，赋值即生效；Mac Catalyst 下关闭按钮（x）默认隐藏、鼠标悬浮到 Tab 上才出现，同时该 Tab 底色点亮成选中色。详见下文「[定制 Tab 条外观](#定制-tab-条外观)」
- **键盘快捷键**：iPad / Mac Catalyst 下按 `Command+W` 关闭当前选中的 Tab；所有 Tab 都关闭后可按配置弹出「是否退出 App」确认框，弹框开关为 `DetailHostViewController.showExitPromptWhenAllTabsClosed`（默认开启），退出动作可用 `exitAction` 自定义
  - **Mac Catalyst 下真正生效的是底层事件监听**：⌘W 是系统菜单 “Close Window” 的*按键等价（key equivalent）*，由 AppKit 在 `NSWindow` 上执行 `performClose:`，优先级高于 `UIKeyCommand`，所以只加 `keyCommands` / 只删菜单项都拦不住。库内新增 `CatalystKeyInterceptor`，用 `NSEvent` 本地事件监听在按键等价处理之前把 ⌘W 截下
  - iPad 仍走 `UIKeyCommand`；`buildMenu` 移除 `.close` 菜单项 + `canPerformAction` 拦截 `performClose:` 作为 UIKit 层的补充
  - 若 App 使用多窗口（多个 `UIWindowScene`），建议同时在 `AppDelegate` 中 `override buildMenu(with:)` 移除 `.close` 菜单（主菜单是全局单例）
- **DeviceHelper / WindowManager**：设备判断与多窗口（新窗口）能力
- **同时兼容两套生命周期**：UIScene 生命周期（iOS 27 SDK 起 Apple 强制要求，见 [TN3187](https://developer.apple.com/documentation/Technotes/tn3187-Migrating-to-the-UIKit-scene-based-life-cycle)）与传统 AppDelegate 生命周期，见下文「[生命周期兼容](#生命周期兼容uiscene--appdelegate)」

> 示例 / Demo：`ArticleListViewController.swift`、`DataStore.swift`、`AppDelegate.swift` 位于宿主层（与 `AppDelegate` 平级），**不随 pod / SPM 发布**。它们是仓库自带的完整接线示例；集成时请用你自己的列表控制器，只需让它持有 `PPContentRouting` 并产出 `PPContentItem` 即可。

> 底层的 `PPTabBarController` 为内部实现类型，**未对外公开**，请通过下面的入口 API 使用。

## 安装

### 方式一：本地路径（开发调试）

在你的 App 工程的 `Podfile` 里：

```ruby
pod 'MultiTabController', :path => '../MultiTabController'   # 指向本仓库根目录（podspec 所在目录）
```

### 方式二：远程仓库（发布后）

```ruby
pod 'MultiTabController', :git => 'https://github.com/wooodypan/iOSDemoHub.git', :tag => '1.0.0'
```

然后执行 `pod install`。

### 方式三：Swift Package Manager

SPM 与 CocoaPods 共用同一份库源码与版本号（`Package.swift` 位于仓库根目录，版本取自 git tag）。

**在 Xcode 里添加**：`File → Add Package Dependencies...` → 输入仓库地址
`https://github.com/wooodypan/iOSDemoHub.git`（版本选 `1.0.0` 或以上）。

**或直接编辑你的 `Package.swift`**：

```swift
dependencies: [
    .package(url: "https://github.com/wooodypan/iOSDemoHub.git", from: "1.0.0"),
],
// 你的 target 里声明：
// .target(name: "YourApp", dependencies: ["MultiTabController"])
```

本地开发调试也可以用路径依赖：

```swift
.package(path: "../MultiTabController")   // 指向本仓库根目录（Package.swift 所在目录）
```

添加后在代码里 `import MultiTabController` 即可使用，用法与下文完全一致。

## 基础用法

按设备分别提供「iPhone 根」与「iPad·Mac 根」，由 `RootBuilder` 分发：

```swift
import MultiTabController

// @main / AppDelegate 中：
let iPhoneRoot: () -> UIViewController = {
    // 你的 iPhone 布局：列表包进标签栏，点内容走 PPPhoneContentRouter
    // （PPTabBarController 是库内部类型，集成方通常用自己已有的标签栏 / 导航容器）
    ...
}
let iPadOrMacRoot: () -> UIViewController = {
    let router = PPSplitContentRouter()
    // 左栏内容控制器由调用方注入，例如包着若干列表的容器，列表各装上一个 router
    let sidebar = /* 你的左栏内容控制器 */
    return SplitContainerViewController(leftViewController: sidebar, router: router)
}
window?.rootViewController = RootBuilder.makeRoot(iPhoneRoot: iPhoneRoot, iPadOrMacRoot: iPadOrMacRoot)
```

自己组装标签栏（`TabBarBuilder` 返回的是 `UIViewController`，可直接当根或嵌入容器）：

> 以下为仓库内 Demo 的接线方式（`ArticleListViewController` / `DataStore` 不随库发布，仅作示例）。

```swift
import MultiTabController

let techList = ArticleListViewController(articles: DataStore.techArticles, title: "Tech")
let newsList = ArticleListViewController(articles: DataStore.newsArticles, title: "News")
let techNav = UINavigationController(rootViewController: techList)
let newsNav = UINavigationController(rootViewController: newsList)

let root = TabBarBuilder.build(viewControllers: [techNav, newsNav], titles: ["Tech", "News"])
window?.rootViewController = root
```

让列表「点开内容」走自定义路由（协议化，解耦设备环境）：

```swift
import MultiTabController

// iPhone 环境：列表在导航栈里，直接 push 详情页
let router = PPPhoneContentRouter(sourceViewController: techList)
techList.router = router
```

## 定制 Tab 条外观

右侧多 Tab 宿主的 Tab 条默认长这样：

- 单个 Tab 只圆**上面两个角**（半径 8pt），下面两个角保持直角，底边与 Tab 条的底边对齐 —— 看起来像浏览器标签页那样「从底边长出来」，而不是浮在半空；
- Tab 顶部与 Tab 条顶边留 **5pt** 间距（单元格高度 = Tab 条高度 44pt − 5pt）；
- 选中 Tab 底色默认浅灰，未选中默认透明（露出 Tab 条自身的底色 `UIColor(white: 0.92, alpha: 1)`）；
- **Mac Catalyst 下关闭按钮（x）是悬浮显示的**：默认藏起来，鼠标悬浮到该 Tab 上才出现（对齐网页里的 CSS hover）；**悬浮的判定粒度是整个 Tab**（指针落在标题上也算），此时整个 Tab 的底色（`contentView.backgroundColor`）会变成 `tabSelectedBackgroundColor`，指针移出即恢复。触摸平台（iPhone / iPad）没有悬浮这个概念，x 一直显示、底色不随指针变。

**选中 / 未选中底色已开放给外部**，赋值后已经在屏幕上的 Tab 会立刻改色（库里只重刷已有单元格，不会重建整条 Tab 条）：

| 属性 | 默认值 | 说明 |
|---|---|---|
| `DetailHostViewController.tabSelectedBackgroundColor` | `UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1)` | 选中 Tab 的底色，作用在单元格的 `contentView.backgroundColor` 上 |
| `DetailHostViewController.tabUnselectedBackgroundColor` | `.clear` | 未选中 Tab 的底色 |

```swift
import MultiTabController

// iPad / Mac：宿主由分栏容器内部创建，容器已把 detailHost 公开出来，直接拿它改色
let split = SplitContainerViewController(
    leftViewController: sidebar,
    router: router,
    contentViewControllerProvider: { MyContentViewController() }
)
split.detailHost.tabSelectedBackgroundColor = .white                            // 选中：白底
split.detailHost.tabUnselectedBackgroundColor = UIColor(white: 0.85, alpha: 1)  // 未选中：深一点的灰
window?.rootViewController = split
```

自己直接持有宿主也可以，改法一样：

```swift
let host = DetailHostViewController(contentViewControllerProvider: { MyContentViewController() })
host.tabSelectedBackgroundColor = .white
host.tabUnselectedBackgroundColor = UIColor(white: 0.85, alpha: 1)
```

> 这两个属性可以在 `init` 之后立刻设置（此时视图还没加载），也可以在运行中随时改，两种时机都生效。
> 只有颜色是开放项：Tab 条高度（44pt）、顶部间距（5pt）、左右内边距（5pt）与圆角半径（8pt）目前是库内的固定值，
> 集中在 `DetailTabBarMetrics` 里，暂时不对外暴露。

## 生命周期兼容（UIScene / AppDelegate）

**背景**：Apple 技术说明 [TN3187](https://developer.apple.com/documentation/Technotes/tn3187-Migrating-to-the-UIKit-scene-based-life-cycle)
规定，**用 iOS 27 SDK 构建的 App 必须采用 UIScene 生命周期**，否则一启动就断言失败：

```
Application failed to launch: UIScene life cycle is required for apps built with this SDK.
```

本库不依赖任何一套生命周期 —— 你迁不迁移都能用，因为它把「窗口从哪来」这件事收敛成了
`AppLifecycle` + `RootBuilder.makeWindow(windowScene:…)` 两个入口。

### 库里提供了什么

| API | 作用 |
|---|---|
| `AppLifecycle.mode` / `AppLifecycle.usesSceneLifecycle` | 运行时判断宿主走的是哪套生命周期（判据与 TN3187 完全一致：Info.plist 里有非空的 `UIApplicationSceneManifest`，**或** AppDelegate 实现了 `application(_:configurationForConnecting:options:)`） |
| `AppLifecycle.activeWindowScene` | 当前活跃的 `UIWindowScene`；传统生命周期下为 `nil` |
| `AppLifecycle.activeWindow` | 当前该用的那个窗口：Scene 生命周期取场景的 `keyWindow`，传统生命周期取 `AppDelegate.window`。库内部（`WindowManager`）已经统一走它，所以两种生命周期下「新窗口 / 找顶层控制器」行为一致 |
| `AppLifecycle.supportsMultipleScenes` | 是否具备开「真多窗口」的条件（Scene 生命周期 + `UIApplicationSupportsMultipleScenes = YES`） |
| `RootBuilder.makeWindow(windowScene:iPhoneRoot:iPadOrMacRoot:)` | Scene 生命周期建「窗口 + 根控制器」：`UIWindow(windowScene:)`，frame 由系统给 |
| `RootBuilder.makeWindow(iPhoneRoot:iPadOrMacRoot:)` | 传统生命周期（含 iOS 12）建「窗口 + 根控制器」，**不需要 `#available` 包一层** |

### 接入方式一：UIScene 生命周期（iOS 27 推荐）

**第一步**：`Info.plist` 里加场景清单（Xcode 的 General → Deployment Info → 勾选「Scene manifest」也行）：

```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <false/>
    <key>UISceneConfigurations</key>
    <dict>
        <key>UIWindowSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneConfigurationName</key>
                <string>Default Configuration</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
            </dict>
        </array>
    </dict>
</dict>
```

> ⚠️ 两个坑：① `UISceneDelegateClassName` 在 **Swift 工程里必须带模块前缀**（`$(PRODUCT_MODULE_NAME).SceneDelegate`）——
> UIKit 用 `NSClassFromString` 找类，只写裸类名 `SceneDelegate` 会找不到，表现是「配了却仍然断言崩」；
> ② Build Settings 里的 **`INFOPLIST_KEY_UIApplicationSceneManifest_Generation` 必须保持 `NO`**，
> 它若为 YES，Xcode 会生成一份 `UISceneConfigurations` 为空的清单覆盖你手写的配置（表现：黑屏 / 依旧判定没采用）。

**第二步**：把建窗口的动作搬到 `SceneDelegate`：

```swift
import UIKit
import MultiTabController

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // 窗口 + 根控制器：库的统一入口，只比传统写法多传一个 windowScene
        let window = RootBuilder.makeWindow(
            windowScene: windowScene,
            iPhoneRoot: { /* 你的 iPhone 根 */ },
            iPadOrMacRoot: { /* 你的 iPad / Mac 根 */ }
        )
        self.window = window
        window.makeKeyAndVisible()
    }
}
```

`AppDelegate` 只保留进程级逻辑（`application(_:didFinishLaunchingWithOptions:)` 照常会被调用），**不要在它里面碰 `self.window`**。

### 接入方式二：传统 AppDelegate 生命周期

不配 `UIApplicationSceneManifest` 就一直走这套（老工程零改动）：

```swift
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let window = RootBuilder.makeWindow(     // 这个重载不带场景参数，iOS 12 部署目标也能直接调
        iPhoneRoot: { /* … */ },
        iPadOrMacRoot: { /* … */ }
    )
    self.window = window
    window.makeKeyAndVisible()
    return true
}
```

两种路线传入的根构建闭包是同一份，所以以后切换生命周期，业务 UI 一行都不用改。

### 迁移时最容易漏的四类回调

Apple 的说明很直白：**一旦采用 Scene 生命周期，下面这些 `UIApplicationDelegate` 方法 UIKit 就不会再调用了 —— 哪怕实现还留在那里。**
所以这是「搬代码」，不是「加配置」：

| 传统生命周期 | Scene 生命周期 |
|---|---|
| `applicationDidBecomeActive:` | `sceneDidBecomeActive:` |
| `applicationWillResignActive:` | `sceneWillResignActive:` |
| `applicationDidEnterBackground:` | `sceneDidEnterBackground:` |
| `applicationWillEnterForeground:` | `sceneWillEnterForeground:` |
| `applicationWillTerminate:` | `sceneDidDisconnect:` |
| `application:openURL:options:` | `scene:openURLContexts:`（**返回值变 void**，一次可能来多个 URL） |
| `application:continueUserActivity:restorationHandler:` | `scene:continueUserActivity:` |
| `didFinishLaunchingWithOptions` 的 `launchOptions` | `connectionOptions.urlContexts` / `.notificationResponse` / `.userActivities` |

`application(_:didFinishLaunchingWithOptions:)` 本身仍然会被调用，进程级逻辑（注册推送、初始化 SDK、崩溃上报）留在原地即可。

### 在本仓库 Demo 里切换两种生命周期

本仓库的 Xcode 工程当前走 **Scene 生命周期**（`MultiTabController/SceneDelegate.swift`）。
要验证**传统生命周期**那条路，把 `MultiTabController/Info.plist` 里的 `UIApplicationSceneManifest` 整块删掉再编译即可 ——
代码一行都不用改：`AppDelegate` 里的 `if !AppLifecycle.usesSceneLifecycle` 分支会自动接管建窗口，
这也是 `AppLifecycle` 这个运行时判定的直接用途。

## 系统要求

- iOS 15.0+
- Swift 5.7+（代码使用了 Swift 5.7 的 `guard let self` 简写）
- 支持 Mac Catalyst

## License

[MIT](LICENSE)
