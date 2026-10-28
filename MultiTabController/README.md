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
- **Tab 编辑状态（未保存修改的灰点）**：把 Tab 标成「编辑中」后，关闭按钮 x 会换成灰色小圆点（Windows 11 记事本那种未保存标识）；Mac Catalyst 下鼠标悬浮时灰点再换回可点击的 x。状态可由内容页通过 `contentHost` 自报，也可由集成方按内容 id 设置。详见下文「[Tab 编辑状态](#tab-编辑状态未保存修改的灰点)」
- **键盘快捷键**：iPad / Mac Catalyst 下按 `Command+W` 关闭当前选中的 Tab；所有 Tab 都关闭后可按配置弹出「是否退出 App」确认框，弹框开关为 `DetailHostViewController.showExitPromptWhenAllTabsClosed`（默认开启），退出动作可用 `exitAction` 自定义
  - **Mac Catalyst 下真正生效的是底层事件监听**：⌘W 是系统菜单 “Close Window” 的*按键等价（key equivalent）*，由 AppKit 在 `NSWindow` 上执行 `performClose:`，优先级高于 `UIKeyCommand`，所以只加 `keyCommands` / 只删菜单项都拦不住。库内新增 `CatalystKeyInterceptor`，用 `NSEvent` 本地事件监听在按键等价处理之前把 ⌘W 截下
  - iPad 仍走 `UIKeyCommand`；`buildMenu` 移除 `.close` 菜单项 + `canPerformAction` 拦截 `performClose:` 作为 UIKit 层的补充
  - 若 App 使用多窗口（多个 `UIWindowScene`），建议同时在 `AppDelegate` 中 `override buildMenu(with:)` 移除 `.close` 菜单（主菜单是全局单例）
- **DeviceHelper / WindowManager**：设备判断与多窗口（新窗口）能力
- **PPAppearance**：App 内手动切换浅色 / 深色，不跟系统。`PPAppearance.mode = .dark` 一行生效，可选持久化记忆；默认仍是跟随系统，iOS 12 上自动无效。详见下文「[App 内手动切换浅色 / 深色](#app-内手动切换浅色--深色)」
- **冷启动恢复上次的 Tab**：`PPTabRestoration.enable { ... }` 一行接入，**默认关闭**（不打开时零副作用）。全局开关 + 单宿主覆盖，多窗口可各存一份；恢复 Tab 顺序、选中项、预览标记与空 Tab。详见下文「[冷启动恢复上次的 Tab](#冷启动恢复上次的-tab)」
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
- 选中 Tab 底色默认是动态色（浅色下浅灰、深色下深灰），未选中默认透明（露出底下的容器底色 `UIColor.pp_systemBackground`）；
- **Mac Catalyst 下关闭按钮（x）是悬浮显示的**：默认藏起来，鼠标悬浮到该 Tab 上才出现（对齐网页里的 CSS hover）；**悬浮的判定粒度是整个 Tab**（指针落在标题上也算），此时整个 Tab 的底色（`contentView.backgroundColor`）会变成 `tabSelectedBackgroundColor`，指针移出即恢复。触摸平台（iPhone / iPad）没有悬浮这个概念，x 一直显示、底色不随指针变。

**选中 / 未选中底色已开放给外部**，赋值后已经在屏幕上的 Tab 会立刻改色（库里只重刷已有单元格，不会重建整条 Tab 条）：

| 属性 | 默认值 | 说明 |
|---|---|---|
| `DetailHostViewController.tabSelectedBackgroundColor` | `UIColor.pp_tabSelectedBackground`（浅色 `#F2F2F2` / 深色 `#474747`） | 选中 Tab 的底色，作用在单元格的 `contentView.backgroundColor` 上 |
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

## Tab 编辑状态（未保存修改的灰点）

Tab 可以标成「编辑中」：关闭按钮的位置改成一个灰色小圆点，提示这里有没保存的修改 —— 抄的是 Windows 11 记事本的行为。

| 状态 | 触摸平台（iPhone / iPad） | Mac Catalyst |
|---|---|---|
| 非编辑态 | 一直显示关闭按钮 `x` | 平时不显示，指针悬浮到该 Tab 上才显示 `x`（原有行为） |
| 编辑态 | 只显示灰色小圆点；**点圆点即关闭该 Tab** | 平时显示灰点；指针悬浮时灰点换回可点击的 `x`，同时 Tab 底色点亮 |

灰点的直径固定 8pt，正好落在 `x` 的位置上，两者同一时刻只露一个。状态只影响视觉，不改变「预览 / 正式 Tab」「选中项」等任何既有语义。

### API

| 成员 | 说明 |
|---|---|
| `setEditing(_:forItemID:)` | 按内容 id 设置 / 取消编辑态，只重刷那一个单元格 |
| `setEditing(_:forContentViewController:)` | 按内容页实例设置。内容页自报走的也是这里 |
| `isEditing(forItemID:)` | 读某个内容当前是否编辑态 |
| `clearAllEditingStates()` | 一次性复位所有编辑态（「全部保存」场景） |
| `closeTab(forItemID:)` | 按内容 id 关闭 Tab。库唯一对外暴露的关闭入口 |
| `shouldCloseTab` | 关闭前的确认钩子，返回 `false` 取消这次关闭（给未保存修改挡一层确认框） |
| `tabEditingIndicatorColor` | 灰点颜色，默认 `UIColor.pp_editingIndicator`（浅色 `#9E9E9E` / 深色半透明白），赋值即生效 |
| `PPContentHosting.contentViewController(_:didChangeEditingState:)` | 内容页 -> 宿主的上报方法，有默认空实现，老接入方不用改代码 |

### 接入方式一：内容页自己上报（推荐）

编辑器自己最清楚「脏没脏」，改完顺手报一次就行：

```swift
final class MyEditorViewController: UIViewController, PPContentDisplaying {
    weak var contentHost: PPContentHosting?   // 必须 weak，否则和宿主循环引用

    private var hasUnsavedChanges = false {
        didSet {
            // 每次输入都调也没关系：宿主发现状态没变就直接跳过，不会重复重绘。
            contentHost?.contentViewController(self, didChangeEditingState: hasUnsavedChanges)
        }
    }
}
```

### 接入方式二：集成方按内容 id 设置

保存、另存、导入这类由外部触发的场景，直接按 id 改：

```swift
// 有未保存修改：Tab 上的 x 变成灰点
split.detailHost.setEditing(true, forItemID: "tech-1")

// 保存完成：灰点变回 x
split.detailHost.setEditing(false, forItemID: "tech-1")

// 全部保存
split.detailHost.clearAllEditingStates()
```

### 关 Tab 前挡一层确认

灰点本身就能点（触摸平台），要避免误关丢内容，用 `shouldCloseTab` 拦一下。钩子是**同步**返回的，
所以姿势是「先返回 false 拦下，用户确认后再关」：

```swift
split.detailHost.shouldCloseTab = { [weak split] item, isEditing in
    guard isEditing, let item = item else { return true }   // 没有未保存修改：直接关

    let alert = UIAlertController(title: "还有未保存的修改", message: "关闭会丢掉这些修改。", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "放弃修改", style: .destructive) { _ in
        // 先清编辑态（否则钩子会再拦一次），再关。
        split?.detailHost.setEditing(false, forItemID: item.id)
        split?.detailHost.closeTab(forItemID: item.id)
    })
    split?.present(alert, animated: true)
    return false
}
```

### 边界与坑

- **不持久化**：编辑态不写进冷启动快照。未保存的内容本来就没法还原，恢复出来的 Tab 一律按「干净」处理。
- **预览槽位复用时自动复位**：`openPreview` 复用同一个预览 Tab 换内容时，宿主动手把编辑态清成 `false`，不会把上一份内容的灰点挂到新内容上。
- **Tab 还不存在时上报无效**：内容页在 `configure(with:)` 里同步上报的话，那一刻 Tab 还没建出来，宿主会直接忽略。想让初始就是脏状态，请在 `viewDidAppear` 之后或由外部调 `setEditing(_:forItemID:)`。
- **按 id 只命中第一个**：`setEditing(_:forItemID:)` / `closeTab(forItemID:)` 只改第一个匹配的 Tab。关掉 `deduplicateOpenedItems` 后，同一个内容可以开成多个 Tab，这种场景请用 `setEditing(_:forContentViewController:)` 精确定位。
- **别和 `didChangeEditedState` 搞混**：那个是「预览 Tab 要不要固定成正式 Tab」（VS Code 语义），这个只管灰点的显隐，两者互不影响，可以同时上报。
- **iOS 12 可用**：只用了 `UIView` + `cornerRadius`，没有新 API。`pp_editingIndicator` 在 iOS 12 上退回浅色那一份。

## 同步左侧列表高亮（选中项回调）

右侧多 Tab 宿主会在**选中项变化**时通知外部：点 Tab、打开 / 复用内容、关闭 Tab 后自动切到相邻 Tab，都会触发。
左侧列表（文件树、文章列表等）可以据此高亮对应行，做出 VS Code 资源管理器那种「右边切哪个，左边亮哪个」的联动。

两种接入方式二选一，都会触发：

```swift
import MultiTabController

// 方式一：闭包（简单场景）
split.detailHost.onSelectedItemChanged = { item in
    // item == nil：当前没有选中内容（所有 Tab 已关闭，或选中的是空 Tab）
    sidebar.setHighlightedItemID(item?.id)   // ← 换成你自己的列表高亮方法
}

// 方式二：代理（需要多处监听、或想按职责拆开时）
final class SidebarSelectionCoordinator: DetailHostViewControllerDelegate {
    func detailHost(_ host: DetailHostViewController, didSelectItem item: PPContentItem?) {
        sidebar.setHighlightedItemID(item?.id)   // ← 同上
    }
}
let coordinator = SidebarSelectionCoordinator()
split.detailHost.delegate = coordinator   // delegate 是 weak，记得自己强持有 coordinator
```

补充约定：

- 当前选中项可以直接通过 `split.detailHost.selectedItem` 读取（`nil` 表示没有选中内容）。
- 给 `delegate` / `onSelectedItemChanged` **赋值时会立刻按当前选中项回调一次**，所以晚接入也能补上初始高亮。
- 回调按**内容 id** 去重：关闭未选中的 Tab 等「选中项其实没变」的场景不会重复通知；预览 Tab 被复用、内容换掉时会通知，因为 id 变了。
- `delegate` 是 `weak` 引用；`onSelectedItemChanged` 由宿主强持有，闭包里请用 `weak` 捕获外部对象。
- 仓库内 Demo 的接线见 `DemoRootFactory.makeiPadOrMacRoot()`：右侧切到另一分类的内容时，左侧标签栏也会自动切过去并高亮该行。

## 冷启动恢复上次的 Tab

右侧多 Tab 宿主可以记住上次打开的 Tab 和选中项，下次启动自动还原。

**这个能力默认关闭。** 不打开时库完全不读 `UserDefaults`、不建任何 Tab，行为和没有它时一模一样 —— 升级上来的项目不会突然多出几个标签页。

### 最小接入（2 步）

```swift
// 1) 启动时打开，并告诉库「内容 id 怎么还原成 PPContentItem」。
//    放在 application(_:didFinishLaunchingWithOptions:) 里、建窗口之前即可。
PPTabRestoration.enable { DataStore.item(withID: $0) }

// 2) 数据层提供同步、O(1) 的反查。
static func item(withID id: String) -> PPContentItem? {
    itemsByID[id]
}
```

时序是安全的：`didFinishLaunchingWithOptions` 一定早于任何 `DetailHostViewController` 的 `viewDidLoad`（Scene 生命周期下窗口在 `SceneDelegate` 才建，传统生命周期下窗口在同一方法里稍后才建）。

> resolver 必须是**同步、O(1) 的本地查表**：它在启动阶段、主线程上被逐条调用，不能发网络请求。
> 如果业务数据是异步加载的，请先把数据准备好再建根控制器，或者先不要开启这个能力。

### API

全局（`PPTabRestoration`，`@MainActor`）：

| API | 类型 | 默认值 | 语义 |
|---|---|---|---|
| `isEnabled` | `Bool` | `false` | 功能总开关。赋值本身不读盘不写盘，只是一份「给之后首次加载的宿主看的配置」 |
| `persistenceKey` | `String` | `"PPTabRestoration"` | 存档键。关闭时完全不生效；不接受 `nil` |
| `contentResolver` | `((String) -> PPContentItem?)?` | `nil` | 内容 id 反查。返回 `nil` = 这条内容确实没了 |
| `enable(resolver:)` | 方法 | — | 默认键 + 打开，一行接入的主入口 |
| `enable(persistenceKey:resolver:)` | 方法 | — | 自定义键（多窗口 / 要存多份时用） |
| `disable()` | 方法 | — | 只关卡，**不删数据** |
| `resetPersistedTabs()` | 方法 | — | 只删存档，**不关当前 Tab** |

单宿主覆盖（`DetailHostViewController`，三个属性默认都是 `nil` = 跟随全局）：

| 属性 | 语义 |
|---|---|
| `restoresTabsOnLaunch: Bool?` | `nil` 跟随全局；`true` / `false` 只覆盖本宿主（例如辅助窗口不恢复） |
| `tabRestorationKey: String?` | 本宿主专用的存档键，`nil` 用全局键 |
| `tabRestorationResolver: ((String) -> PPContentItem?)?` | 本宿主专用的解析器，`nil` 用全局 resolver |

合并规则：

```text
enabled  = restoresTabsOnLaunch ?? PPTabRestoration.isEnabled
resolver = tabRestorationResolver ?? PPTabRestoration.contentResolver
key      = tabRestorationKey ?? PPTabRestoration.persistenceKey
```

三项都齐才生效，否则整个能力按关闭处理。

### 多窗口

同一个键被两个窗口共用时会互相覆盖（谁最后操作 Tab，谁的状态留下，下次两个窗口又都恢复成那一份）。
`viewDidLoad` 时宿主还没进窗口（`view.window` 是 `nil`），库没法自动按场景区分，所以要显式指定：

```swift
func scene(_ scene: UIScene,
           willConnectTo session: UISceneSession,
           options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }

    let window = RootBuilder.makeWindow(
        windowScene: windowScene,
        iPhoneRoot: { DemoRootFactory.makeiPhoneRoot() },
        iPadOrMacRoot: {
            let split = /* 构建你的分栏根 */
            // 必须在返回之前设置：窗口装根控制器时就会触发 split.viewDidLoad，
            // 而它内部 embed(detailHost) 会当场触发宿主的 viewDidLoad。
            split.detailHost.tabRestorationKey = "PPTabRestoration." + session.persistentIdentifier
            return split
        }
    )
    self.window = window
    window.makeKeyAndVisible()
}
```

单窗口 App 什么都不用做，共用一个全局键即可。

### 原理与边界

- **只求值一次**：宿主在 `viewDidLoad` 里读一次配置并缓存。运行期改全局开关只影响之后才首次加载的宿主，**不会追溯**已经上屏的宿主（配置项也必须在宿主 view 首次加载前设置）。
- **恢复不写盘**：resolver 返回 `nil` 的条目只跳过、不改写存档，避免一次数据未就绪就把用户历史永久删掉；等用户下一次真正操作 Tab 时才写入新快照。
- **空 Tab 也恢复**：`id` 存 `nil`，恢复后仍是一个标题为 "New Tab" 的空 Tab，不调 `configure`。
- **保存的是下标不是 id**：关掉 `deduplicateOpenedItems` 时同一个内容可以有多个 Tab，用 id 无法区分；恢复时也不去重，按原样还原。
- **预览标记保留**：`isPreview` 会一起存；脏数据里出现多个预览 Tab 时只认第一个，保证预览槽唯一。
- **有安全上限**：最多恢复 50 个 Tab（库内固定值，防脏数据一次拉起成百上千个控制器）。
- **`resetPersistedTabs()` 只清存档**，不会关闭当前 Tab；宿主还活着时下一次操作会立刻写回。
- **iOS 12 可用**：只依赖 `Codable` / `JSONEncoder` / `UserDefaults.data`，都是 iOS 12 之前就有的 API。
- **别和 `PPAppearance.persistenceKey` 共用键**：两者数据格式不同，会互相覆盖。
- iPhone 路径（`PPPhoneContentRouter` + 导航栈 push）不归这个能力管，开启后对它没有任何影响。

### 验证方法

在 iPad / Mac 上打开 3 个 Tab（含一个预览、一个空 Tab），切到第 2 个 → 杀掉 App 重启 → Tab 数量、顺序、选中项、预览斜体、空 Tab 都应一致；把 `enable` 那行注释掉再试一次，应该完全不恢复。

## 深色模式（夜间模式）

库内所有颜色都走**系统语义色**，所以集成方不需要写任何代码 —— 系统切到深色，界面自动跟着变（前提是 App 没有把 `UIUserInterfaceStyle` 锁成 Light）。
想反过来：在 App 内手动锁死浅色 / 深色、不跟系统，看下一节 `PPAppearance`。

| 界面元素 | 颜色来源 |
|---|---|
| 容器 / 内容区背景 | `UIColor.pp_systemBackground`（浅色白 / 深色黑） |
| 选中 Tab 底色 | `DetailHostViewController.tabSelectedBackgroundColor`，默认 `UIColor.pp_tabSelectedBackground` |
| 左右分栏线、底部标签栏上边线 | `UIColor.pp_separator` |
| Tab 条与内容区之间的细线 | `UIColor.pp_hairlineSeparator` |
| Tab 标题、侧栏按钮图标 | `UIColor.pp_label` |
| 编辑态灰点 | `DetailHostViewController.tabEditingIndicatorColor`，默认 `UIColor.pp_editingIndicator` |
| 占位文案 | `UIColor.pp_tertiaryLabel` |

这些语义色集中定义在库内的 `UIColor+Compatibility.swift`：

- **iOS 13+** 直接返回系统动态色（`.systemBackground`、`.label`、……）。动态色是「解析时才求值」的，系统切换外观时 UIKit 会自动重新解析并重绘，不需要手动刷新页面；
- **iOS 12** 没有系统级深色模式（深色模式是 iOS 13 才引入的），固定返回浅色那一份，表现与旧版本完全一致。

想换成自己的配色，用 `UIColor.pp_adaptive(light:dark:)` 造一个动态色，再赋给公开变量即可：

```swift
split.detailHost.tabSelectedBackgroundColor = .pp_adaptive(
    light: UIColor(white: 0.93, alpha: 1.0),
    dark: UIColor(white: 0.30, alpha: 1.0)
)
```

> ⚠️ 一个容易踩的坑：`CALayer` 的 `borderColor` 是 `CGColor`，**不参与动态色解析**，外观切换时不会自动更新，
> 需要在 `traitCollectionDidChange(_:)`（iOS 17+ 建议用 `registerForTraitChanges`）里手动重设。
> 库内的 Tab 单元格没有使用 layer 描边，所以不受影响；自己扩展样式时请留意。

## App 内手动切换浅色 / 深色

只跟系统不够用 —— 用户想在 App 里自己锁死浅色或深色（阅读类、看板类 App 很常见）。
库提供了 `PPAppearance`，一行代码切换，不需要自己遍历视图树改 `overrideUserInterfaceStyle`。

### 最小接入（3 步）

```swift
// 1. 启动时读回上次的选择。放在建窗口之前，两种生命周期都会走 didFinishLaunching
PPAppearance.restore()

// 2. 照常用库的 RootBuilder 建窗口 —— 外观会被自动套上，这里不用写任何额外代码
let window = RootBuilder.makeWindow(windowScene: windowScene, // 或传统生命周期的重载
                                    iPhoneRoot: { ... },
                                    iPadOrMacRoot: { ... })

// 3. 需要切换的地方直接赋值，立刻生效
PPAppearance.mode = .dark
```

### API

| 成员 | 说明 |
|---|---|
| `PPAppearance.mode` | 当前模式，可读可写。赋值立刻应用到所有窗口并广播通知 |
| `PPAppearanceMode` | `.system` / `.light` / `.dark`；`displayName` 是可直接显示的默认文案 |
| `PPAppearance.persistenceKey` | UserDefaults 键，默认 `"PPAppearanceMode"`；设成 `nil` 就关掉持久化 |
| `PPAppearance.restore()` | 读回上次保存的值，没存过或值非法时保持当前值 |
| `PPAppearance.reset()` | 清掉保存的值并回到跟随系统（给「恢复默认设置」用） |
| `PPAppearance.apply(to:)` | 套到指定窗口。自己 new `UIWindow`（没用 `RootBuilder`）时调它 |
| `PPAppearance.applyToAllWindows()` | 套到所有窗口。setter 会自动调，只有运行期新开的窗口才需要补 |
| `Notification.Name.ppAppearanceDidChange` | 切换后广播，用来刷新不会自动变的东西 |

### 原理与边界

实现是在 `UIWindow` 上设 `overrideUserInterfaceStyle`，页面代码一行都不用改。
选窗口而不是逐个 ViewController，是因为窗口是 trait 的源头 —— 覆盖一处就能覆盖整棵视图树，包括之后 push / present 出来的页面。

| 行为 | 说明 |
|---|---|
| 已有的动态色 | 自动重新解析并重绘，刷新逻辑不用写 |
| `CALayer.borderColor` / `shadowColor` | 是 CGColor，**不会自动变**，监听 `.ppAppearanceDidChange` 自己用 `resolvedColor(with:)` 重算 |
| iOS 12 | **无效**。`UIUserInterfaceStyle` 是 iOS 13 的类型，页面保持浅色。想藏掉入口用 `if #available(iOS 13.0, *)` |
| 系统设置 | 只覆盖 App 自己的外观，不影响系统，也不影响其他 App |
| 多窗口 | 所有窗口一起覆盖；后面新开的窗口要补一次 `applyToAllWindows()` |

### 自定义入口

入口长什么样、放在哪里完全由宿主决定，库只认 `PPAppearance.mode`。
仓库 Demo 做成了列表页导航栏上的「外观」按钮 + ActionSheet 三选（见 `ArticleListViewController`）。
换成 SegmentedControl 或设置页开关同理：

```swift
@IBAction func styleChanged(_ sender: UISegmentedControl) {
    // rawValue 顺序与分段顺序一致：0 跟随系统 / 1 浅色 / 2 深色
    PPAppearance.mode = PPAppearanceMode(rawValue: sender.selectedSegmentIndex) ?? .system
}

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
