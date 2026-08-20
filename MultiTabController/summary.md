# MultiTabController 从 0 构建全记录

> 一份"施工日志 + 教程"，讲清楚这个支持 **iPhone 单 TabBar、iPad/Mac 浏览器式多 Tab 分屏** 的 iOS App 是怎么一步步搭起来的。
> 目标读者：会一点 Swift/UIKit、想搞懂"不用 Storyboard、不用 SceneDelegate、纯代码做多 Tab 容器"的同学。

---

## 目录

1. [这个 App 是做什么的](#1-这个-app-是做什么的)
2. [环境与前提](#2-环境与前提)
3. [整体架构一览](#3-整体架构一览)
4. [从 0 到 1：十个构建阶段](#4-从-0-到-1十个构建阶段)
   - 阶段一：干掉 SceneDelegate，纯代码启动
   - 阶段二：数据模型与假数据
   - 阶段三：设备分发 RootContainerViewController
   - 阶段四：列表页 ArticleListViewController
   - 阶段五：详情页 DetailViewController（含输入框示例）
   - 阶段六：iPad/Mac 左右分屏 CustomSplitViewController
   - 阶段七：浏览器式多 Tab 管理器
   - 阶段八：把根容器组件化
   - 阶段九：VS Code 式"复用 Tab"策略
   - 阶段十：新窗口（模态，不保活）
5. [核心设计模式](#5-核心设计模式)
6. [踩过的坑](#6-踩过的坑)
7. [如何运行](#7-如何运行)
8. [文件清单](#8-文件清单)
9. [可扩展方向](#9-可扩展方向)

---

## 1. 这个 App 是做什么的

需求来自 `README.md`，一句话概括：**一个"类浏览器"的多标签阅读器**。

- **iPhone**：底部 `UITabBarController`，Tech / News 两个列表 Tab，点列表行 `push` 进详情。
- **iPad / Mac Catalyst**：顶部一条"浏览器式"Tab 栏（`UICollectionView` 做的），每个 Tab 是一个左右分屏（左列表、右详情），可以"+ 新建"、"× 关闭"，**切换 Tab 不销毁内容（保活）**。
- **关键约束**：不使用 `UISceneDelegate`；用最朴素的 `addChild(_:)` 手动做视图控制器嵌套；支持 Mac Catalyst。

---

## 2. 环境与前提

| 项 | 值 |
| --- | --- |
| 语言 | Swift（UIKit） |
| IDE | Xcode 26（构建环境 17A324） |
| 部署目标 | iOS 15.6（README 原写 iOS 12，实际工程设为 15.6） |
| Mac Catalyst | 已开启（Targets → General → Mac Catalyst） |
| 入口方式 | 纯代码，**无 Main.storyboard、无 SceneDelegate** |
| 数据 | 内置假数据（`DataStore`），无需网络 |

> 为什么不用 SceneDelegate？需求明确要求"不使用 UISceneDelegate 相关 API"，所以我们走**传统 App 生命周期**：自己 `new` 一个 `UIWindow`。

---

## 3. 整体架构一览

```
AppDelegate（@main，手动创建 UIWindow）
   └── RootContainerViewController（根容器，按设备二选一）
         ├── [iPhone]  UITabBarController（addChild）
         │      ├── Tech:  UINavigationController → ArticleListViewController
         │      └── News:  UINavigationController → ArticleListViewController
         │           点行 → pushViewController(DetailViewController)
         │
         └── [iPad/Mac]  BrowserTabManagerViewController（addChild）
                ├── 顶部 Tab 栏（UICollectionView）：每个 item 是一个 BrowserTab
                └── 内容区：当前激活 Tab 的 CustomSplitViewController（addChild）
                       ├── 左侧 leftContainerView → UITabBarController（Tech/News 列表）
                       └── 右侧 rightContainerView → DetailViewController（addChild）
```

核心思想：**一切嵌套都靠 `addChild` + `didMove(toParent:)` 手写容器**，不依赖 `UISplitViewController`/`UINavigationController` 的黑盒（当然列表外仍包了一层 `UINavigationController` 以便 iPhone push）。

---

## 4. 从 0 到 1：十个构建阶段

### 阶段一：干掉 SceneDelegate，纯代码启动

Xcode 模板默认会生成 `SceneDelegate.swift` 并在 `Info.plist` 里写 `UIApplicationSceneManifest`。我们：

1. 删除 `SceneDelegate.swift`、`ViewController.swift`、`Main.storyboard`（这些是模板遗留的死代码，工程中无任何引用）。
2. `Info.plist` 清空为 `<dict></dict>`，在 `project.pbxproj` 里保留 `UILaunchStoryboardName = LaunchScreen`、移除 `UIMainStoryboardFile`。
3. 在 `AppDelegate` 里手动建窗口：

```swift
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    // 必须持有 window：系统启动完成后会通过 KVC 把窗口赋值到这里
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = RootContainerViewController() // 根容器
        window?.makeKeyAndVisible()
        return true
    }
}
```

> 工程用 `PBXFileSystemSynchronizedRootGroup`（Xcode 26 的新特性）：被同步目录下的 `.swift` 文件**自动加入编译**，删除文件即从编译移除，不需要手改 `pbxproj` 的 file reference。

### 阶段二：数据模型与假数据

`DataModel.swift` 一个结构体 + 一个静态数据源，纯内存、零依赖：

```swift
struct Article {
    let id: Int
    let title: String
    let body: String
    let category: String
}

struct DataStore {
    static let techArticles: [Article] = (1...20).map {
        Article(id: $0, title: "Tech Article \($0)", body: "...", category: "Tech")
    }
    static let newsArticles: [Article] = (1...20).map {
        Article(id: $0 + 100, title: "News Article \($0)", body: "...", category: "News")
    }
}
```

### 阶段三：设备分发 RootContainerViewController

`DeviceHelper` 用编译期宏 + 运行期判断区分平台：

```swift
enum DeviceLayout { case iPhone; case iPadOrMac }

struct DeviceHelper {
    static var currentLayout: DeviceLayout {
        #if targetEnvironment(macCatalyst)
        return .iPadOrMac
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPadOrMac : .iPhone
        #endif
    }
}
```

`RootContainerViewController` 在 `viewDidLoad` 里按设备选布局（详见阶段八的组件化版本）：

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    setupLayout()
}
private func setupLayout() {
    switch DeviceHelper.currentLayout {
    case .iPadOrMac: setupBrowserTabLayout()   // → BrowserTabManagerViewController
    case .iPhone:      setupiPhoneTabBarLayout() // → UITabBarController
    }
}
```

### 阶段四：列表页 ArticleListViewController

左列 `UITableView` + 假数据。这里有两个"进阶点"：

**(a) iPhone / iPad 行为不同**：iPhone 点击行直接 `push`；iPad/Mac 点击行通过回调告诉父容器（避免自己 push）。

**(b) 单击 vs 双击**：为了后面实现 VS Code 式策略，用两个 `UITapGestureRecognizer` 区分"预览"和"正式打开"：

```swift
private func setupTapGestures() {
    let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
    doubleTap.numberOfTapsRequired = 2

    let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
    singleTap.numberOfTapsRequired = 1
    // 关键：等系统确认"不是双击"后，单击才触发，避免双击时误触发一次预览
    singleTap.require(toFail: doubleTap)

    tableView.addGestureRecognizer(singleTap)
    tableView.addGestureRecognizer(doubleTap)
}
```

回调暴露给外部：

```swift
var onArticleSelected: ((Article) -> Void)?        // 单击 = 预览
var onArticleDoubleSelected: ((Article) -> Void)?  // 双击 = 正式打开
```

### 阶段五：详情页 DetailViewController（含输入框示例）

详情页展示文章，并提供了一个**"输入文字就改变 Bool"的示范**——这正是需求里要的演示：

```swift
// 关键 Bool 属性：记录用户是否在备注框里输入过内容
var isEdited: Bool = false
// 内容变化时回调：true=已输入（固定当前 Tab），false=已清空
var onEditStateChanged: ((Bool) -> Void)?

private let noteTextField = UITextField()

@objc private func textChanged() {
    guard !isResetting else { return } // configure 程序化清空时不触发
    let hasText = !(noteTextField.text ?? "").isEmpty
    isEdited = hasText                  // ← 输入文字，这个 Bool 就变成 true
    onEditStateChanged?(hasText)        // 通知父容器（用来把当前 Tab 固定）
}
```

> `isResetting` 是个小技巧：切换文章时 `configure(with:)` 会清空输入框，但这属于"程序化重置"，不应该当作"用户编辑"，所以用 `isResetting` 临时屏蔽回调。

### 阶段六：iPad/Mac 左右分屏 CustomSplitViewController

不用 `UISplitViewController`，而是手写左右两个容器视图，用 `addChild` 把子控制器塞进去：

```swift
private let leftContainerView = UIView()
private let rightContainerView = UIView()

private func setupLeftSide() {
    let tabBar = UITabBarController()
    let techNav = UINavigationController(rootViewController: techListVC)
    let newsNav = UINavigationController(rootViewController: newsListVC)
    tabBar.viewControllers = [techNav, newsNav]
    addChild(tabBar)                       // ① 成为子控制器
    leftContainerView.addSubview(tabBar.view)
    tabBar.didMove(toParent: self)        // ② 通知完成添加
}

private func setupRightSide() {
    let detail = DetailViewController()
    detail.onEditStateChanged = { [weak self] hasText in
        self?.isPinned = hasText          // 把"已编辑"状态记到分屏上
        self?.onTabPinned?(hasText)       // 转发给 Tab 管理器
    }
    addChild(detail)
    rightContainerView.addSubview(detail.view)
    detail.didMove(toParent: self)
}
```

它的角色是**"事件中转站"**：把左侧列表的选中、右侧详情的编辑，都通过回调转发给 `BrowserTabManagerViewController`，自己不决定"建不建 Tab"。

### 阶段七：浏览器式多 Tab 管理器

`BrowserTabManagerViewController` 是 iPad/Mac 的核心。要点：

- **Tab 模型** `BrowserTab`：持有 `CustomSplitViewController` 的**强引用** → 切换 Tab 时只移走 `view`，VC 不销毁 → **保活**。

```swift
class BrowserTab {
    let id: UUID
    var title: String
    let splitVC: CustomSplitViewController   // 强引用，保证状态不丢
    var isPreview: Bool                       // 阶段九新增：是否为可复用的预览 Tab
    init(title: String, splitVC: CustomSplitViewController, isPreview: Bool = true) { ... }
}
```

- **顶部 Tab 栏**用 `UICollectionView` 实现，最后一个 cell 是"+"。
- **切换 Tab**（`switchToTab`）就是前面那套 `willMove/toParent` 移除旧、添加新。

```swift
func switchToTab(at index: Int, animated: Bool = true) {
    guard index >= 0, index < tabs.count else { return }
    activeTabIndex = index
    let newVC = tabs[index].splitVC
    if let current = currentChildVC {        // 移除旧的（只移 view，不销毁 VC）
        current.willMove(toParent: nil)
        current.view.removeFromSuperview()
        current.removeFromParent()
    }
    addChild(newVC)                          // 添加新的
    newVC.view.frame = contentContainerView.bounds
    contentContainerView.addSubview(newVC.view)
    newVC.didMove(toParent: self)
    currentChildVC = newVC
}
```

启动时默认开一个**空的预览 Tab**（可被首次单击复用）：

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    setupTabBarCollectionView()
    setupContentContainer()
    openNewTab(article: nil, isPreview: true, animated: false)
}
```

### 阶段八：把根容器组件化

最早 `RootContainerViewController` 把 `ArticleListViewController` 写死在内部。需求要求它变成**可复用组件**：传入任意 `[UIViewController]` + 标题即可。改造如下：

```swift
class RootContainerViewController: UIViewController {
    private let contentViewControllers: [UIViewController]
    private let tabTitles: [String]

    // 指定初始化器：外部传入子控制器数组 + 标题
    init(viewControllers: [UIViewController], titles: [String]) {
        self.contentViewControllers = viewControllers
        self.tabTitles = titles
        super.init(nibName: nil, bundle: nil)
        setupTabBarItems()
    }

    // 便捷初始化器（无参）：保留原默认 Tech/News 行为，AppDelegate 调用照旧
    convenience init() {
        let techNav = UINavigationController(rootViewController:
            ArticleListViewController(articles: DataStore.techArticles, title: "Tech"))
        let newsNav = UINavigationController(rootViewController:
            ArticleListViewController(articles: DataStore.newsArticles, title: "News"))
        self.init(viewControllers: [techNav, newsNav], titles: ["Tech", "News"])
    }

    // 每个 VC 按索引生成 UITabBarItem
    private func setupTabBarItems() {
        for (i, vc) in contentViewControllers.enumerated() {
            let title = i < tabTitles.count ? tabTitles[i] : "Tab \(i + 1)"
            vc.tabBarItem = UITabBarItem(title: title, image: nil, tag: i)
        }
    }

    private func setupiPhoneTabBarLayout() {
        let tabBar = UITabBarController()
        tabBar.viewControllers = contentViewControllers  // 直接等于传入数组
        addChild(tabBar); /* ... */
    }
}
```

> 用法：`RootContainerViewController()` 仍是默认 Tech/News；想自定义就 `RootContainerViewController(viewControllers: [vc1, vc2], titles: ["A", "B"])`。

### 阶段九：VS Code 式"复用 Tab"策略

参考 `VS Code复用tab策略.md`：单击=Preview（可复用，占用同一个 Preview 槽位）；双击=正式 Tab（不复用）；**编辑 Preview 内容会把它固定为正式 Tab**。

原项目不满足（没有预览/正式之分），改造后逻辑在 `BrowserTabManagerViewController`：

```swift
// 单击文章：预览策略
private func handleArticlePreviewSelected(_ article: Article) {
    if let previewIdx = tabs.firstIndex(where: { $0.isPreview }) {
        // 已有 Preview Tab → 复用它（加载文章、改标题、切过去）
        tabs[previewIdx].splitVC.showDetail(article: article)
        tabs[previewIdx].title = article.title
        switchToTab(at: previewIdx)
    } else {
        // 没有 Preview Tab（当前都是正式 Tab）→ 新建一个 Preview Tab
        openNewTab(article: article, isPreview: true)
    }
}
```

双击 / "+" / "在新 Tab 打开" 都走 `openNewTab(article:isPreview:false)`（正式、不复用）。

**"输入文字 → 固定为正式 Tab"的链路**（这就是阶段五那个输入框的作用）：

```
DetailViewController.textChanged()
  → detail.isEdited = true
  → onEditStateChanged(true)
  → CustomSplitViewController.isPinned = true
  → onTabPinned(true)
  → BrowserTabManagerViewController: tabs[idx].isPreview = false   // 固定！
```

固定之后，再**单击**左侧文章：因为已没有 Preview Tab，于是 `handleArticlePreviewSelected` 走 `else` 分支 → **新建一个 Preview Tab**，而不是覆盖当前这个正式 Tab。这正是需求要的效果。

为了肉眼可见，`TabBarCell` 里预览 Tab 用**斜体 + 浅色**、正式 Tab 用正常字体：

```swift
func configure(title: String, isActive: Bool, isAddButton: Bool, isPreview: Bool = false) {
    titleLabel.text = title
    // ...
    titleLabel.font = isPreview
        ? UIFont.italicSystemFont(ofSize: 13)   // 预览：斜体，强调可复用
        : UIFont.systemFont(ofSize: 13)         // 正式：正常，强调已固定
}
```

### 阶段十：新窗口（模态，不保活）

`DetailViewController` 上有"在新窗口中打开"按钮。`WindowManager` 用 `present` 模态弹出一个 `NewWindowViewController`，**dismiss 后无强引用 → 自动销毁**（与多 Tab 的"保活"形成对比）：

```swift
private static func openAsModal(article: Article) {
    guard let topVC = topViewController() else { return }
    let nav = UINavigationController(rootViewController: NewWindowViewController(article: article))
    nav.modalPresentationStyle = .pageSheet
    topVC.present(nav, animated: true)
}
```

> Catalyst 上 `UIApplication.shared.keyWindow` 不可用，`WindowManager.keyWindow()` 按 `#if targetEnvironment(macCatalyst)` 改为从 `connectedScenes` 取窗口。

---

## 5. 核心设计模式

### addChild 标准四步

```swift
// 添加子控制器
addChild(childVC)
view.addSubview(childVC.view)
childVC.didMove(toParent: self)

// 移除子控制器
childVC.willMove(toParent: nil)
childVC.view.removeFromSuperview()
childVC.removeFromParent()
```

### 多 Tab 保活

`BrowserTab` 持有 `splitVC` 强引用，切换只是 `view` 的搬移，VC 对象始终在 `tabs` 数组里 → 状态不丢。

### 事件转发链（避免"上帝控制器"）

```
ArticleListViewController（点列表）
   → CustomSplitViewController（中转）
      → BrowserTabManagerViewController（决策：复用/新建 Tab）
```

每个层级只关心自己那点事，职责清晰。

### 设备分支

统一在 `RootContainerViewController` 一处 `switch DeviceHelper.currentLayout`，其余 VC 不关心平台。

---

## 6. 踩过的坑

| 坑 | 现象 | 解决 |
| --- | --- | --- |
| Catalyst 无 `keyWindow` | `UIApplication.shared.keyWindow` 编译/运行报错 | `#if targetEnvironment(macCatalyst)` 下从 `connectedScenes` 取 `UIWindowScene` |
| `DetailViewController` 初始化器 | 自定义 `init(article:)` 变指定初始化后，`DetailViewController()` 无参调用报错 | 重写 `init(nibName:bundle:)` 继承 `UIViewController()`，再加 `convenience init(article:)` |
| 双击误触发预览 | 单击/双击都打到列表 | `singleTap.require(toFail: doubleTap)` |
| 切换文章清输入框误判"已编辑" | `configure` 清文本触发 `onEditStateChanged` | `isResetting` 标志屏蔽程序化清空 |
| 删文件还进编译 | 旧模板 `SceneDelegate` 残留 | `PBXFileSystemSynchronizedRootGroup` 下直接 `rm` 即出编译；确认无引用后删除 |

---

## 7. 如何运行

1. Xcode 打开 `MultiTabController.xcodeproj`。
2. 真机/iPhone 模拟器 → 看 **iPhone 布局**；iPad 模拟器或 Mac Catalyst（勾选 My Mac）→ 看 **浏览器式多 Tab 分屏**。
3. iPad/Mac 下体验策略：单击列表=复用预览 Tab（斜体）；输入备注=固定为正式 Tab（正常字体）；再单击=新建 Tab；双击=强制新建正式 Tab。
4. 命令行构建校验：`xcodebuild -scheme MultiTabController -configuration Debug -destination 'generic/platform=iOS Simulator' build` → **BUILD SUCCEEDED**。

---

## 8. 文件清单

```
MultiTabController/
├── AppDelegate.swift                     # 入口，手动创建 UIWindow，无 SceneDelegate
├── Info.plist                           # 空 dict（启动屏走 pbxproj 的 UILaunchStoryboardName）
├── MultiTabController/
│   ├── DataModel.swift                  # Article 模型 + DataStore 假数据
│   ├── DeviceHelper.swift               # iPhone / iPadOrMac 布局判断
│   ├── RootContainerViewController.swift# 根容器：按设备分发 + [UIViewController] 组件化
│   ├── ArticleListViewController.swift  # 列表页（UITableView + 单击/双击手势）
│   ├── DetailViewController.swift       # 详情页（含备注输入框 + isEdited 示例）
│   ├── CustomSplitViewController.swift  # 手写左右分屏（addChild）+ 事件中转
│   ├── BrowserTabManagerViewController.swift # iPad/Mac 多 Tab 管理器（含 VS Code 策略）
│   ├── WindowManager.swift              # 新窗口（模态，不保活）+ NewWindowViewController
│   └── README.md                        # 原始需求说明
└── VS Code复用tab策略.md                 # 本项目的 Tab 策略参考
```

> 注：源码实际位于 `MultiTabController/MultiTabController/` 双层目录下（Xcode 模板的目录嵌套），逻辑结构如上。

---

## 9. 可扩展方向

- **iPhone 也支持双击/固定**：目前双击只在 iPad/Mac 生效，iPhone 仍是纯 push。
- **持久化 Tab**：现在多 Tab 在内存，重启即丢，可接 `UserDefaults`/本地数据库。
- **Preview 数量上限**：VS Code 可配置"编辑器组 Preview 数量"，可加参数。
- **把 iPad/Mac 分支也参数化**：`BrowserTabManagerViewController` 目前仍内置 Tech/News 列表，可像 `RootContainerViewController` 一样接收外部 VC 数组。

---

*构建记录：Xcode 26 / iOS 15.6，纯代码、无 SceneDelegate、Mac Catalyst 开启。所有源码含面向初级程序员的逐行中文注释。*
