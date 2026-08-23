# MultiTabDemo — Swift iOS/macOS Catalyst

使用swift语言开发一个app demo，不使用UISceneDelegate相关API，使用最简单的子UIViewController添加到父UIViewController操作API，比如addChild(_ childController: UIViewController)，实现如果设备是macOS和iPad就显示左右分屏，左侧是UITableView，右侧是详情，左侧是2个UINavigationController+UIViewController构成的页面，嵌入PPTabBarController，可以使用UISplitViewController也可以使用addChild(_ childController: UIViewController)把两个子UIViewController添加到父UIViewController来自定义一个SplitViewController。而iPhone只使用PPTabBarController，点击列表后通过pushViewController跳转到详情。
跳转详情的时候，不管是啥设备，每次跳转都支持打开新tab或新窗口，如果是打开新tab1，支持页面保活，下次打开另一个新tab2,还能看到tab1的数据，可以使用UICollectionView和addChild(_ childController: UIViewController)实现类似浏览器那样的多tab页面，如果是打开新窗口，返回就直接销毁。
要求最低支持iOS11或12，且支持mac catalyst，给我示例代码，该简单的地方可以非常简单，比如PPTabBarController的子UIViewController可以用一个按钮替代UITableView



优化下代码，右侧 DetailViewController 如果还有2级界面，采用navigationController?.pushViewController(viewController, animated: true)的方式跳转到2级界面

优化下代码,默认打开0个tab，右侧用DetailViewController显示占位文字。
点击左侧列表时，如果点击了第1行，且以tab页的方式打开，未创建过的话就创建一个DetailViewController展示在右侧，而不是把新页面的标题通过updateActiveTabTitle更新。如果点击了第2行和第3行等，且以tab页的方式打开，未创建过的话就创建一个DetailViewController，跟第一行类似。如果点击其他行后再次点击第1行，第一行对应的DetailViewController存在，就切换到第1个tab页。

PPTabBarController的两个子UIViewController，各自管理一个右侧的DetailViewController，当点击News这个Tab新创建一个跟News关联的DetailViewController。点击Tech和News后右侧的DetailViewController实例不相同，切换Tech和News时不销毁PPTabBarController的Tech和News各自关联的DetailViewController



，就跳转到DetailViewController
的左侧对齐
Tech和News不要公用一个DetailViewController
BrowserTabManagerViewController的tabs属性可以最少0个BrowserTab，当关闭所有tab时，显示一个占位界面，
DetailViewController顶部左上角加一个按钮，可以隐藏ArticleListViewController，隐藏的过程加一个动画，模拟UISplitViewController收起masterViewController的效果。

// 用 addChild 手动实现左右分屏：
//   左侧：PPTabBarController（内含2个 NavigationController+ListVC）
//   右侧：DetailViewController
## 工程结构

```
MultiTabDemo/
├── AppDelegate.swift                   # 入口，无 UISceneDelegate
├── DeviceHelper.swift                  # 设备布局判断
├── DataModel.swift                     # 数据模型
├── RootBuilder.swift                  # 根控制器工厂，按设备直接产出 rootViewController
├── TabBarBuilder.swift                # 组件化：传入 [UIViewController]+标题 → PPTabBarController
├── SplitContainerViewController.swift   # iPad/Mac 根：左右分栏（左 PPTabBarController + 右 DetailHostViewController）
├── DetailHostViewController.swift       # 右侧多 Tab 详情宿主（含 VS Code 预览/正式策略、保活）
├── ArticleRouters.swift                 # 协议化路由：ArticleOpenMode / ArticleOpenRouting / Phone·Split Router
├── ArticleListViewController.swift     # 列表页（UITableView）
├── DetailViewController.swift          # 详情页
├── WindowManager.swift                 # 新窗口管理
└── Info.plist
```

## 布局策略

### iPhone
```
RootBuilder.makeRoot() → PPTabBarController（由 TabBarBuilder 构造，直接当 root）
        ├── Tab 1: UINavigationController → ArticleListViewController
        │              点击行 → pushViewController(DetailViewController)
        └── Tab 2: UINavigationController → ArticleListViewController
```

### iPad / Mac Catalyst
```
RootBuilder.makeRoot() → SplitContainerViewController（直接当 root，左右分栏）
        ├── 左栏 [leftContainerView]
        │     └── PPTabBarController (addChild)
        │           ├── Tech: ArticleListViewController（router=splitRouter）
        │           └── News: ArticleListViewController（router=splitRouter）
        └── 右栏 [rightContainerView]
              └── DetailHostViewController (addChild)
                    ├── [Tab Bar: UICollectionView] ← 浏览器式多 Tab 条
                    │       每个 Tab 持有一个 DetailViewController（保活）
                    └── [Content Area] ← 当前激活 Tab 的 DetailViewController
```

## 核心设计

### 多 Tab 保活
`DetailTabItem` 对象持有 `DetailViewController` 的**强引用**，
切换 Tab 时只是将其 view 隐藏/显示（或移除/添加），
ViewController 本身不销毁 → **状态保活**。

```swift
// 切换时：移除旧 VC 的 view，但 VC 对象由 tabs 数组持有，不销毁
current.willMove(toParent: nil)
current.view.removeFromSuperview()
current.removeFromParent()

// 添加新 VC
addChild(newVC)
contentContainerView.addSubview(newVC.view)
newVC.didMove(toParent: self)
```

### 新窗口（不保活）
通过 `present(nav, animated: true)` 模态弹出，
dismiss 后 VC 无强引用 → **自动销毁**。

### addChild 标准用法
```swift
// 添加
addChild(childVC)
view.addSubview(childVC.view)
childVC.didMove(toParent: self)

// 移除
childVC.willMove(toParent: nil)
childVC.view.removeFromSuperview()
childVC.removeFromParent()
```

## 如何运行

1. Xcode 14+，新建 **iOS App** 工程（Swift，Storyboard）
2. **删除** Main.storyboard 及 Info.plist 中的 `UIMainStoryboardFile` 键
3. **删除** SceneDelegate.swift，并移除 Info.plist 中的 `UIApplicationSceneManifest`
4. 将本工程所有 `.swift` 文件复制进去
5. Deployment Target 设为 **iOS 12.0**
6. 如需 Mac Catalyst：Targets → General → **Mac Catalyst** 勾选

## Info.plist 关键配置

- **不含** `UIApplicationSceneManifest` （禁用 SceneDelegate）
- **不含** `UIMainStoryboardFile` （纯代码）
- `UILaunchStoryboardName` = `LaunchScreen`（保留启动屏）
