# MultiTabController

一套可复用的 iOS UI 组件，用于构建「左侧分类列表 + 右侧多 Tab 详情宿主」的分栏界面，
并实现了类似 VS Code 的 Tab 复用策略（预览 / 正式 / 固定）。已适配 **iPhone、iPad 与 Mac Catalyst**。

## 功能特性

- **RootBuilder**：按设备自动选择布局
  - iPhone → 标签栏（`Tech` / `News` 两个列表，点文章 push 详情）
  - iPad / Mac → 分栏根控制器（左列表 + 右 `DetailHostViewController` 多 Tab 详情宿主）
- **ArticleListViewController**：左侧列表，用单击（预览）/ 双击（正式）手势对应 VS Code Tab 策略
- **DetailViewController**：右侧详情页，含「标记为已编辑 / 清除编辑标记」示例，用于固定当前 Tab
- **DetailHostViewController**：右侧多 Tab 宿主，承载 VS Code 预览/正式语义
- **ArticleOpenRouting**：协议化路由，把「列表点开文章」的意图与具体设备环境解耦
- **DeviceHelper / WindowManager**：设备判断与多窗口（新窗口）能力

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

最简单的方式——直接把库产出的根控制器设为窗口根：

```swift
import MultiTabController

// AppDelegate / SceneDelegate 中：
window?.rootViewController = RootBuilder.makeRoot()
```

自己组装标签栏（`TabBarBuilder` 返回的是 `UIViewController`，可直接当根或嵌入容器）：

```swift
import MultiTabController

let techList = ArticleListViewController(articles: DataStore.techArticles, title: "Tech")
let newsList = ArticleListViewController(articles: DataStore.newsArticles, title: "News")
let techNav = UINavigationController(rootViewController: techList)
let newsNav = UINavigationController(rootViewController: newsList)

let root = TabBarBuilder.build(viewControllers: [techNav, newsNav], titles: ["Tech", "News"])
window?.rootViewController = root
```

让列表「点开文章」走自定义路由（协议化，解耦设备环境）：

```swift
import MultiTabController

let router = PhoneArticleRouter(sourceViewController: techList)
techList.router = router
```

## 系统要求

- iOS 15.0+
- Swift 5.7+（代码使用了 Swift 5.7 的 `guard let self` 简写）
- 支持 Mac Catalyst

## License

[MIT](LICENSE)
