MultiTabController 从 0 构建全记录

> 一份"施工日志 + 教程"，讲清楚这个支持 **iPhone 单 TabBar、iPad/Mac 左右分栏 + 右侧浏览器式多 Tab 详情宿主** 的 iOS App 是怎么一步步搭起来的。
> 目标读者：会一点 Swift/UIKit、想搞懂"不用 Storyboard、不用 SceneDelegate、纯代码做多 Tab 容器"的同学。

---

## 目录

1. [这个 App 是做什么的](#1-这个-app-是做什么的)
2. [环境与前提](#2-环境与前提)
3. [整体架构一览](#3-整体架构一览)
4. [从 0 到 1：十个构建阶段](#4-从-0-到-1十个构建阶段)
   - 阶段一：干掉 SceneDelegate，纯代码启动
   - 阶段二：数据模型与假数据
   - 阶段三：设备分发 RootBuilder（工厂）
   - 阶段四：列表页 ArticleListViewController
   - 阶段五：详情页 DetailViewController（含按钮示例）
   - 阶段六：iPad/Mac 左右分栏 SplitContainerViewController + 协议化路由
   - 阶段七：右侧详情宿主 DetailHostViewController（多 Tab 下沉）
   - 阶段八：抽出根控制器工厂 + TabBarBuilder 组件化
   - 阶段九：VS Code 式"复用 Tab"策略（落于详情宿主）
   - 阶段十：新窗口（模态，不保活）
5. [核心设计模式](#5-核心设计模式)
6. [踩过的坑](#6-踩过的坑)
7. [如何运行](#7-如何运行)
8. [文件清单](#8-文件清单)
9. [可扩展方向](#9-可扩展方向)

---

## 1. 这个 App 是做什么的

需求来自 `README.md`，一句话概括：**一个"类浏览器"的多标签阅读器**。

- **iPhone**：底部 `PPTabBarController`，Tech / News 两个列表 Tab，点列表行 `push` 进详情。
- **iPad / Mac Catalyst**：左右分栏，左栏是 `PPTabBarController`（Tech/News 列表），右栏是一个"浏览器式多 Tab 详情宿主"`DetailHostViewController`（`UICollectionView` Tab 条 + 内容区），可以"× 关闭"、**切换 Tab 不销毁内容（保活）**。VS Code 式预览/正式策略落在这个右侧宿主里。
- **关键约束**：不使用 `UISceneDelegate`；用最朴素的 `addChild(_:)` 手动做视图控制器嵌套；支持 Mac Catalyst。

---

## 2. 环境与前提

| 项           | 值                                                |
| ------------ | ------------------------------------------------- |
| 语言         | Swift（UIKit）                                    |
| IDE          | Xcode 26（构建环境 17A324）                       |
| 部署目标     | iOS 15.6（README 原写 iOS 12，实际工程设为 15.6） |
| Mac Catalyst | 已开启（Targets → General → Mac Catalyst）        |
| 入口方式     | 纯代码，**无 Main.storyboard、无 SceneDelegate**  |
| 数据         | 内置假数据（`DataStore`），无需网络               |

> 为什么不用 SceneDelegate？需求明确要求"不使用 UISceneDelegate 相关 API"，所以我们走**传统 App 生命周期**：自己 `new` 一个 `UIWindow`。

---

## 3. 整体架构一览

```
AppDelegate（@main，手动创建 UIWindow）
   └── RootBuilder.makeRoot()（工厂：按设备直接产出根控制器）
         ├── [iPhone]  PPTabBarController（由 TabBarBuilder 构造）
         │      ├── Tech:  UINavigationController → ArticleListViewController
         │      └── News:  UINavigationController → ArticleListViewController
         │           点行 → pushViewController(DetailViewController)
         │
         └── [iPad/Mac]  SplitContainerViewController（直接当 root，左右分栏）
                ├── 左栏 leftContainerView → PPTabBarController（Tech/News 列表，router=splitRouter）
                └── 右栏 rightContainerView → DetailHostViewController（addChild）
                       ├── 顶部 Tab 条（UICollectionView）：每个 item 是一个详情 Tab
                       └── 内容区：当前激活 Tab 的 DetailViewController（addChild，保活）
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
        window?.rootViewController = RootBuilder.makeRoot() // 工厂按设备产出根控制器
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

### 阶段三：设备分发 RootBuilder（工厂）

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

我们用一个**工厂 `RootBuilder`** 把"按设备选布局"从 AppDelegate 里抽出来，直接产出最终要当 `window.rootViewController` 的控制器，**不再包一层不显示内容的容器 VC**：

```swift
enum RootBuilder {
    // 设备判定是启动期一次性决定，用工厂产出根控制器即可，无需常驻 VC。
    static func makeRoot() -> UIViewController {
        switch DeviceHelper.currentLayout {
        case .iPadOrMac:
            return SplitContainerViewController()            // iPad/Mac：左列表 + 右 DetailHostViewController
        case .iPhone:
            let techNav = UINavigationController(
                rootViewController: ArticleListViewController(articles: DataStore.techArticles, title: "Tech"))
            let newsNav = UINavigationController(
                rootViewController: ArticleListViewController(articles: DataStore.newsArticles, title: "News"))
            return TabBarBuilder.build(viewControllers: [techNav, newsNav], titles: ["Tech", "News"])
        }
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

### 阶段五：详情页 DetailViewController（含按钮示例）

详情页展示文章，并提供了一个**"点击按钮就改变 Bool"的示范**——用两个按钮 + 点击事件来演示某个 UIViewController 的 Bool 属性随交互变化：

```swift
// 关键 Bool 属性：记录当前详情是否被“标记编辑”
var isEdited: Bool = false
// 状态变化时回调：true=已标记（固定当前 Tab），false=已清除
var onEditStateChanged: ((Bool) -> Void)?

// 两个示例按钮共用一个纵向/横向栈
@objc private func markAsEdited() {
    isEdited = true                     // ← 点击“标记为已编辑”，Bool 变 true
    onEditStateChanged?(true)           // 通知父容器（用来把当前 Tab 固定）
}

@objc private func clearEdit() {
    isEdited = false                    // ← 点击“清除编辑标记”，Bool 变回 false
    onEditStateChanged?(false)
}
```

> 用按钮而非输入框，能更直观地演示“点击 → Bool 变化 → 触发回调”的链路：`markAsEdited` 把 `isEdited` 置 `true`，`clearEdit` 置 `false`，两个事件都通过 `onEditStateChanged` 上报。

### 阶段六：iPad/Mac 左右分栏 + 协议化路由

iPad/Mac 的根控制器是 `SplitContainerViewController`：左栏 `PPTabBarController`（Tech/News 列表），右栏一个 `DetailHostViewController`。列表发出的"打开文章"不再直接耦合上层，而是通过 `ArticleOpenRouting` 协议（模仿 NewsSplitDemo 的 `ArticleOpenRouting`）把意图交给 router：

- `ArticleListViewController` 只持有 `var router: ArticleOpenRouting?`，单击(iPad/Mac→`.preview` / iPhone→`.newTab`)、双击(iPad/Mac→`.newTab`)只发意图。
- `PhoneArticleRouter`：iPhone 环境，`push` 详情页。
- `SplitArticleRouter`：iPad/Mac 环境，把意图转交给右侧 `DetailHostViewController`。

```swift
// SplitContainerViewController 里：左列表装上分栏路由，路由解析到右栏详情宿主
let router = SplitArticleRouter()
let list = ArticleListViewController(articles: DataStore.techArticles, title: "Tech")
list.router = router
router.detailHostResolver = { [weak self] _ in self?.detailHost }
```

左栏用 `PPTabBarController`（自定义类，不读 tabBarItem，用 `ButtonConfiguration` 定义 Tab），右栏 `DetailHostViewController` 通过 `embed(_:in:)` 用 `addChild` 嵌入。

### 阶段七：右侧详情宿主 DetailHostViewController（多 Tab 下沉）

把"浏览器式多 Tab"从顶层下沉到右侧详情宿主（模仿 NewsSplitDemo 的 `DetailHostViewController`）：`SplitContainerViewController` 只负责左右分栏，多 Tab 都在右栏的 `DetailHostViewController` 里。它的 Tab 是**一篇文章/一个 `DetailViewController`**（而不是一整个分屏），左栏在切 Tab 时始终不动。

- **Tab 模型** `DetailTabItem`：持有 `DetailViewController` 的**强引用** → 切换 Tab 时只隐藏/显示 `view`，VC 不销毁 → **保活**。
- **顶部 Tab 条**用 `UICollectionView` 实现（`DetailTabCell`：标题 + 关闭按钮）。
- **切换 Tab**（`refreshUI`）：根据 `selectedTabID` 隐藏/显示各 `controller.view`，并把当前那个 `bringSubviewToFront`。

```swift
private struct DetailTabItem {
    let id: String
    var article: Article?
    let controller: DetailViewController   // 强引用，保证状态不丢
    var isPreview: Bool                    // 是否为可复用的预览 Tab
}
```

启动时空宿主，显示占位文案"← 请从左侧选择"；首次单击文章即创建第一个 Tab。

### 阶段八：抽出根控制器工厂 + TabBarBuilder 组件化

最早的根逻辑把 `ArticleListViewController` 写死在内部。我们把"用任意 `[UIViewController]` + 标题构造 `PPTabBarController`"这个能力抽成**可复用的 `TabBarBuilder`**，再把"按设备选布局"抽成 `RootBuilder`，AppDelegate 只调一行：

```swift
// TabBarBuilder：传入子控制器数组 + 标题，产出带正确 Tab 按钮的 PPTabBarController。
// PPTabBarController 是自定义 UIViewController 子类，不读取 tabBarItem，
// 而是通过 buttonConfigurations（标题 + 图标）定义每个 Tab。
enum TabBarBuilder {
    static func build(viewControllers: [UIViewController], titles: [String]) -> PPTabBarController {
        let count = min(viewControllers.count, titles.count)
        let configurations = (0..<count).map { i in
            PPTabBarController.ButtonConfiguration(title: titles[i], image: nil)
        }
        return PPTabBarController(
            viewControllers: Array(viewControllers.prefix(count)),
            buttonConfigurations: configurations
        )
    }
}
```

> 用法：想自定义就 `TabBarBuilder.build(viewControllers: [vc1, vc2], titles: ["A", "B"])`；`RootBuilder.makeRoot()` 在 iPhone 分支内部就是这么用的，iPad/Mac 则直接返回 `SplitContainerViewController`。

这样层级从 `Window → 容器VC → 目标VC` 扁平成 `Window → 目标VC`，AppDelegate 也保持瘦，组件化能力还留在 `TabBarBuilder` 里可单独复用。

### 阶段九：VS Code 式"复用 Tab"策略

参考 `VS Code复用tab策略.md`：单击=Preview（可复用，占用同一个 Preview 槽位）；双击=正式 Tab（不复用）；**编辑 Preview 内容会把它固定为正式 Tab**。

原项目不满足（没有预览/正式之分），改造后逻辑落在右侧详情宿主 `DetailHostViewController` 的 `openPreview` / `openNewTab`：

```swift
// 单击文章：预览策略（复用预览槽位）
func openPreview(_ article: Article) {
    if let index = tabs.firstIndex(where: { $0.isPreview }) {
        // 已有 Preview Tab → 复用它（加载文章、切过去）
        load(article: article, into: index)
        selectedTabID = tabs[index].id
        refreshUI()
    } else {
        // 没有 Preview Tab（当前都是正式 Tab）→ 新建一个 Preview Tab
        appendTab(for: article, isPreview: true)
    }
}
```

双击 / "在新 Tab 打开" 都走 `openNewTab(article:)`（正式、不复用）。

**"点击按钮标记 → 固定为正式 Tab"的链路**（这就是阶段五那两个按钮的作用）：

```
DetailViewController.markAsEdited()
  → detail.isEdited = true
  → onEditStateChanged(true)
  → DetailHostViewController.setPreview(false, for: controller)   // 固定！
```

固定之后，再**单击**左侧文章：因为已没有 Preview Tab，于是 `openPreview` 走 `else` 分支 → **新建一个 Preview Tab**，而不是覆盖当前这个正式 Tab。这正是需求要的效果。

为了肉眼可见，`DetailTabCell` 里预览 Tab 用**斜体**、正式 Tab 用正常字体：

```swift
func configure(title: String, selected: Bool, isPreview: Bool) {
    titleLabel.text = title
    titleLabel.font = isPreview
        ? UIFont.italicSystemFont(ofSize: 14)   // 预览：斜体，强调可复用
        : UIFont.systemFont(ofSize: 14, weight: .semibold)   // 正式：正常，强调已固定
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
   → ArticleOpenRouting（协议：列表只发意图）
      → PhoneArticleRouter / SplitArticleRouter（按设备决策）
         → iPad/Mac: DetailHostViewController（决策：复用/新建 Tab）
```

每个层级只关心自己那点事，职责清晰。

### 设备分支

统一在 `RootBuilder` 一处 `switch DeviceHelper.currentLayout`，其余 VC 不关心平台。

---

## 6. 踩过的坑

| 坑                              | 现象                                                                          | 解决                                                                                      |
| ------------------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Catalyst 无 `keyWindow`         | `UIApplication.shared.keyWindow` 编译/运行报错                                | `#if targetEnvironment(macCatalyst)` 下从 `connectedScenes` 取 `UIWindowScene`            |
| `DetailViewController` 初始化器 | 自定义 `init(article:)` 变指定初始化后，`DetailViewController()` 无参调用报错 | 重写 `init(nibName:bundle:)` 继承 `UIViewController()`，再加 `convenience init(article:)` |
| 双击误触发预览                  | 单击/双击都打到列表                                                           | `singleTap.require(toFail: doubleTap)`                                                    |
| 切换文章时编辑状态残留          | 旧实现清输入框时会误触发 `onEditStateChanged`                                 | 改用两个按钮示例，`configure` 只复位 `isEdited = false` 不触发回调                        |
| 删文件还进编译                  | 旧模板 `SceneDelegate` 残留                                                   | `PBXFileSystemSynchronizedRootGroup` 下直接 `rm` 即出编译；确认无引用后删除               |

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
│   ├── RootBuilder.swift                # 根控制器工厂：按设备直接产出 rootViewController
│   ├── TabBarBuilder.swift              # 组件化：传入 [UIViewController]+标题 → PPTabBarController
│   ├── ArticleListViewController.swift  # 列表页（UITableView + 单击/双击手势）
│   ├── DetailViewController.swift       # 详情页（含按钮示例 + isEdited）
│   ├── SplitContainerViewController.swift  # iPad/Mac 根：左右分栏（左 PPTabBarController + 右 DetailHostViewController）
│   ├── DetailHostViewController.swift      # 右侧多 Tab 详情宿主（含 VS Code 预览/正式策略、保活）
│   ├── ArticleRouters.swift                # 协议化路由：ArticleOpenMode / ArticleOpenRouting / Phone·Split Router
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
- **按分类隔离详情宿主**：可仿 NewsSplitDemo 的 `useSeparateDetailHostPerSidebarTab`，让 Tech / News 各自拥有独立的 `DetailHostViewController`（目前两者共享一个）。

---

_构建记录：Xcode 26 / iOS 15.6，纯代码、无 SceneDelegate、Mac Catalyst 开启。所有源码含面向初级程序员的逐行中文注释。_
