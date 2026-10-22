# 冷启动恢复上次打开的 Tab

## 这个能力在解决什么

用户打开了一堆标签页（Tab），切到某一页看着。把 App 从后台划掉，再打开，标签页全没了，得一个个重新点回来。

「冷启动恢复」就是把这件事自动化：**App 彻底退出后再次启动时，把上次的 Tab 条原样还原出来** —— 有几个 Tab、什么顺序、哪个是预览态、当前停在哪一个，全都一致。

这篇笔记按时间顺序走一遍完整流程。先看全局，再看每一步。

## 先看全局：一次恢复涉及三段

```
【上一次运行】用户操作 Tab
        │
        ├─ 开 Tab / 切 Tab / 关 Tab …
        │      └─→ 立刻把当前状态写成一份 JSON，存进 UserDefaults
        │
        ▼
   （App 被杀掉 / 用户主动退出）
        │
        ▼
【这一次启动】
  1. AppDelegate 打开开关、注册「id → 内容」的查询方法
  2. 建窗口 → 建根控制器 → 建右侧 Tab 宿主（此时还没画界面）
  3. 宿主的 view 第一次加载 → viewDidLoad 里读存档
  4. 逐条把内容查回来、建好控制器、一次性拼成 tabs 数组
  5. 交给一次 reloadData 把结果画到 Tab 条上
  6. 布局完成后滚动到选中的那个 Tab
        │
        ▼
【启动之后】用户继续操作，回到第一段的保存循环
```

一句话概括：**操作时存 → 启动时读 → 一次性重建 → 之后继续存**。

## 涉及的角色

| 角色 | 文件 | 管什么 |
|---|---|---|
| `PPTabRestoration` | `MultiTabController/MultiTabController/PPTabRestoration.swift` | 全局开关 + 存档读写（唯一碰 `UserDefaults` 的地方） |
| `PPTabRestorationSnapshot` | 同上（同文件内部） | 存档的数据结构（`version` / `tabs` / `selectedIndex`） |
| `DetailHostViewController` | `.../DetailHostViewController.swift` | 真正干活的人：决定要不要恢复、重建 Tab、之后负责保存 |
| `SplitContainerViewController` | `.../SplitContainerViewController.swift` | 分栏容器，持有一个 `detailHost`，`viewDidLoad` 时把它嵌进右栏 |
| `RootBuilder` | `.../RootBuilder.swift` | 建窗口、装根控制器 |
| `AppDelegate` | `MultiTabController/AppDelegate.swift` | 启动的第一站，在这里打开开关（宿主层代码，不随库发布） |
| `DataStore` | `MultiTabController/DataStore.swift` | Demo 的数据源，提供 `item(withID:)` 给开关当查询方法 |

> 「宿主层」= Demo 代码，不进 pod / SPM 包。库本身不认识任何具体文章，所以**内容怎么查回来必须由外部告诉它** —— 这就是下面 `resolver` 的作用。

## 第 0 步：先把开关打开（整个流程的前提）

这个能力**默认是关的**。不打开时，库连 `UserDefaults` 都不读，行为和没有这个功能时完全一样。

打开只要一行，放在 `AppDelegate.didFinishLaunchingWithOptions` 里：

```swift
PPTabRestoration.enable(resolver: { DataStore.item(withID: $0) })
```

这里要理解两个词：

- **`resolver`（解析器）**：一个「给内容 id，返回内容」的函数。库里只存了 `"tech-3"` 这样的字符串，它不知道这是哪篇文章，所以启动时要靠这个函数翻译回来。返回 `nil` 表示「这个内容确实没了」。
- **`persistenceKey`**：存档在 `UserDefaults` 里的键名，默认 `"PPTabRestoration"`。一个 App 只有一个宿主时不用管它。

**为什么必须放在这里？** 因为后面第 3 步的 `viewDidLoad` 会去读这个开关。启动顺序是固定的：

```
didFinishLaunchingWithOptions   ← 开关在这里打开（最早）
        ↓
建窗口 / 建根控制器               ← 此时宿主对象才被创建
        ↓
宿主 view 第一次加载（viewDidLoad） ← 读开关，太晚设置就赶不上了
```

`enable` 内部也是按「键 → resolver → 开关」的顺序赋值的，保证任何看到 `isEnabled == true` 的地方，另外两项都已经就位。

## 第一部分：存档是怎么来的（上次运行时）

恢复依赖的前提是「上次存过」。所以先看保存这一侧。

### 存的是什么

一份 JSON，用 `Codable` 编码后塞进 `UserDefaults`：

```json
{
  "version": 1,
  "tabs": [
    { "id": "tech-1", "isPreview": false },
    { "id": null,     "isPreview": false },
    { "id": "tech-3", "isPreview": true  }
  ],
  "selectedIndex": 2
}
```

三个字段各有讲究：

| 字段 | 含义 | 为什么这么设计 |
|---|---|---|
| `id` | 内容的业务 id | **不能存 Tab 自己的 UUID** —— 那个每次启动都重新生成，没法用来找回内容 |
| `id = null` | 这是一个空 Tab（标题 `New Tab`） | 用户上次留着的空白工作区，恢复后应该还是空白 |
| `isPreview` | 是不是预览 Tab | 恢复后要保留「斜体、可被复用」的语义 |
| `selectedIndex` | 选中第几个 | **用下标而不是 id**：关掉去重后，同一篇文章可以开成两个 Tab，用 id 分不清是哪一份 |
| `version` | 格式版本号 | 以后改结构就 +1，旧存档会被当成「没有历史」忽略，不会崩 |

### 什么时候存

**不是退出时存，而是每次 Tab 状态变化就立刻存。** 因为 iOS 上 App 可能被系统直接杀掉，等不到「退出」这个时机。

| 触发点 | 方法 | 状态变了什么 |
|---|---|---|
| 打开新 Tab | `appendTab` | 多了一条，且新 Tab 成为选中项 |
| 复用预览槽位 | `openPreview` | Tab 数量没变，但内容换了 |
| 用户点 Tab | `collectionView(_:didSelectItemAt:)` | 选中项变了 |
| 程序化定位到已有 Tab | `selectTab(at:)` | 选中项变了（去重命中时走这里） |
| 关 Tab | `closeTab(withID:)` | 少了一条，选中项可能顺移 |
| 预览转正式 / 正式转预览 | `setPreview(_:for:)` | `isPreview` 字段变了 |

前五处紧跟在 `notifySelectionChanged()`（通知外部高亮）后面；`setPreview` 不涉及选中项变化，所以只存快照、不通知。

`persistTabsIfNeeded()` 自己会先过三道闸：

1. 正在恢复中？→ 不写（原因见后面第 4 步）
2. 这个宿主当初就没开恢复？→ 不写
3. 一个 Tab 都不剩？→ **删掉键**，而不是写一个空数组（「没有历史」比「空快照」语义更清楚）

> ⚠️ 新手最容易踩的坑：**不要用 `onSelectedItemChanged` 来保存**。那个回调在赋值时就会立刻触发一次（此时 Tab 还是空的），而且它按内容 id 去重 —— 关掉去重后同内容互切根本不会回调。

## 第二部分：这次启动，一步步恢复

### 步骤 1：启动入口，打开开关

`AppDelegate.didFinishLaunchingWithOptions` 执行 `PPTabRestoration.enable(...)`。这一步只写配置，不读盘、不建 Tab。

**关键逻辑**：此处窗口还不存在，也不能碰 `self.window`（Scene 生命周期下必然是 nil）。

### 步骤 2：建窗口 → 建根控制器 → 建宿主（界面还没画）

`SceneDelegate.scene(_:willConnectTo:)` 调 `RootBuilder.makeWindow(...)`：

1. 建 `UIWindow`，先套上外观（`PPAppearance.apply`），再装根控制器；
2. 装根控制器时调 `DemoRootFactory.makeiPadOrMacRoot()`；
3. 它在 `SplitContainerViewController` 的 `init` 里创建了 `detailHost`。

**此刻 `detailHost` 已经存在，但它的 `view` 还是 nil。** 这是整个流程里最关键的一句 —— 后面所有时序问题都源于此。

### 步骤 3：宿主 view 第一次加载，`viewDidLoad` 里做五件事

`SplitContainerViewController.viewDidLoad` 调 `embed(detailHost, ...)`，里面访问了 `childViewController.view`，这才**触发** `DetailHostViewController.viewDidLoad`。

`viewDidLoad` 的执行顺序不能乱：

| 顺序 | 动作 | 作用 |
|---|---|---|
| 1 | `setupViews()` | 搭出 Tab 条、内容区、占位文案 |
| 2 | `refreshUI()` | **先按「没有 Tab」的样子渲染一次**（Tab 条高度压成 0，显示占位文案） |
| 3 | `restoreTabsIfNeeded()` | **冷启动恢复的入口**，见下一步 |
| 4 | `installCatalystKeyInterceptorIfNeeded()` | Mac 下拦 ⌘W，与恢复无关 |
| 5 | `collectionView.reloadData()` | 全量同步集合视图，**把恢复结果当成基线** |

**为什么恢复必须插在第 2 步和第 5 步之间？**

集合视图（`UICollectionView`）有个硬规矩：你告诉它「有 N 条」，再插一条，它内部会核对「插入前 N 条、插入后 N+1 条」。对不上就直接抛 `NSInternalInconsistencyException`。

`reloadData()` 是「重新问数据源有几条」。如果把恢复放在它**后面**，集合视图已经把「0 条」当基线了，你再插 5 条就得补 5 次批量插入，中间任何一次计数不对就崩。

放在它**前面**，恢复只是默默把 `tabs` 数组填好，`reloadData()` 一问就是 5 条 —— 基线天然对齐，一次搞定。

### 步骤 4：`restoreTabsIfNeeded()` 内部

这个方法做的事，按顺序拆成 7 小步。

**① 只跑一次，且「失败也算跑过」**

```swift
guard !didAttemptTabRestoration else { return }
didAttemptTabRestoration = true
```

`didAttemptTabRestoration` 无论开关开着还是关着都会置位。这样**运行期再把全局开关打开，也不会追溯已经上屏的宿主** —— 否则会突然往用户正开着的窗口里塞一堆历史 Tab，等于替换他的工作现场。

**② 合并配置，只求值这一次**

```swift
let enabled  = restoresTabsOnLaunch ?? PPTabRestoration.isEnabled   // 宿主没表态才看全局
let resolver = tabRestorationResolver ?? PPTabRestoration.contentResolver
let key      = tabRestorationKey ?? PPTabRestoration.persistenceKey
```

三个覆盖项都是 `nil` 表示「跟随全局」，这就是「全局开关 + 单宿主可覆盖」的写法：

- 多窗口各存一份 → 给每个宿主设不同的 `tabRestorationKey`；
- 辅助窗口不恢复 → `restoresTabsOnLaunch = false`。

求值结果存进 `restorationConfig`，**保存时也用这一份**，保证「从哪把键读的，就写回哪把键」，不会出现读 A 键写 B 键的错位。

**为什么只在 `viewDidLoad` 求值一次？** 在 `init` 里求值时，外部还没拿到宿主，覆盖项必然全是 `nil`；在属性的 `didSet` 里求值，会撞上「先设 key、再设 resolver、最后设开关」的中间态，把半成品配置固化下来。放在这里拿到的是一份完整、稳定的配置。

配置算不出来（没开 / 没给 resolver / 键是空字符串）就 `return` —— **连 `UserDefaults` 都不读**。

**③ 读存档，解不开就当没有**

```swift
guard let snapshot = PPTabRestoration.loadSnapshot(forKey: config.persistenceKey),
      !snapshot.tabs.isEmpty else { return }
```

`loadSnapshot` 里三种情况都返回 `nil`：没存过、JSON 解不开、`version` 对不上。**静默忽略，不主动清坏数据** —— 万一只是这次读取异常，下次还有机会；真正的覆盖发生在用户下次操作 Tab 时。

**④ 上锁：恢复期间禁止写盘**

```swift
isRestoringTabs = true
defer { isRestoringTabs = false }
```

原因是：此刻 `tabs` 还没替换完，而内容页的 `configure` 里如果上报了编辑态，会走 `setPreview → persistTabsIfNeeded`，把旧存档覆盖成空或半成品。

**⑤ 逐条重建，跳过失效内容**

对存档里的每一条：

```
有 id ？ ── 是 → 调 resolver 查内容
          │        查不到 → continue（跳过这一条，不影响其它）
          └─ 否 → item = nil（空 Tab，照常建）

建一个内容页 controller → 注入 contentHost → 有内容才 configure
addChild + didMove(toParent:)     ← 建立父子关系保活
判断 isPreview（只认第一个预览 Tab，防止脏数据破坏「预览槽位唯一」）
```

三条要点：

- **内容查不到只是跳过这一条，不会因此改写存档。** 一次临时的数据未就绪，不该把用户的历史永久删掉。
- **空 Tab 不 `configure`** —— 它本来就没内容，标题保持默认的 `New Tab`。
- **下标要重新换算**：前面可能有条目被跳过，所以用 `restoredSelectedIndex` 记录「选中项在恢复后数组里的真实位置」，不能直接用存档里的 `selectedIndex`。

这里还有个安全阀：`min(snapshot.tabs.count, maxRestoredTabCount)`，上限 50 条。防的是存档被改坏或旧版本遗留，一次拉起成百上千个控制器。

**⑥ 一次性替换数据源 —— 绝不循环调 `appendTab`**

```swift
tabs = restoredTabs
```

为什么不能一条条 `appendTab`？因为 `appendTab` 每次都会 `refreshUI()` + `performBatchUpdates`：N 个 Tab 就是 N 次布局、N 次插入；而且视图还没上屏时 `append` 还会撞上「基线冲突」（就是步骤 3 说的那个异常）。

**⑦ 定选中项 → 刷新壳 → 标记滚动 → 通知外部**

```swift
let fallbackIndex = min(max(snapshot.selectedIndex, 0), restoredTabs.count - 1)
selectedTabID = restoredTabs[restoredSelectedIndex ?? fallbackIndex].id

refreshUI()                          // 让 Tab 条显示出来、挂上选中的内容页
needsScrollToRestoredSelection = true // 滚动推迟到布局完成
notifySelectionChanged()             // 通知左侧列表高亮
```

下标兜底是必要的：存档里的 `selectedIndex` 可能因为跳过失效内容而越界，`min/max` 把它夹回合法范围。

`notifySelectionChanged()` 不能漏 —— 恢复出来的选中项也是「当前选中项」，左侧列表的高亮要跟着对。

**⑧ 恢复结束，一个字都不写盘**

方法最后**没有** `persistTabsIfNeeded()`。因为上面被 `resolver` 判为 `nil` 的条目还留在存档里，此刻保存等于把它们永久删掉。等用户下一次真正操作 Tab 时再写。

### 步骤 5：`reloadData()` 把结果画出来

回到 `viewDidLoad` 第 5 步。`numberOfItemsInSection` 返回 `tabs.count`，`cellForItemAt` 逐条取标题、选中态、预览态、配色。Tab 条在这一刻才真正有内容。

### 步骤 6：布局完成后，滚动到选中的 Tab

`viewDidLoad` 时视图宽度可能还是 0，此时滚动算不出位置。所以恢复里只设了个标记：

```swift
public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard needsScrollToRestoredSelection, view.bounds.width > 0 else { return }
    needsScrollToRestoredSelection = false
    scrollToSelectedItem(animated: false)
}
```

`width > 0` 是等宽度的条件；滚动不带动画，避免启动时 Tab 条自己滑一下。

到这里，界面上看到的就和上次退出前一样了。

## 时序总表（一张表看完）

| # | 时机 | 位置 | 做什么 | 碰 `UserDefaults` |
|---|---|---|---|---|
| 0 | 启动最早 | `AppDelegate.didFinishLaunchingWithOptions` | `PPTabRestoration.enable(...)` 写配置 | 否 |
| 1 | 建窗口 | `RootBuilder.makeWindow` | 建窗口、套外观、装根控制器 | 否 |
| 2 | 建根 | `SplitContainerViewController.init` | 创建 `detailHost`（view 还没加载） | 否 |
| 3 | 宿主 view 加载 | `SplitContainerViewController.viewDidLoad` → `embed` | 触发 `DetailHostViewController.viewDidLoad` | 否 |
| 4 | 视图就绪 | `viewDidLoad` 内 | `setupViews()` → `refreshUI()` | 否 |
| 5 | 恢复 | `viewDidLoad` 内 `restoreTabsIfNeeded()` | 合并配置 → 读存档 → 重建 → 替换 `tabs` → 定选中 → `refreshUI` | **读** |
| 6 | 同步集合视图 | `viewDidLoad` 末 | `reloadData()` 把恢复结果当基线 | 否 |
| 7 | 布局完成 | `viewDidLayoutSubviews` | 首次滚动到选中项 | 否 |
| 8 | 用户操作 | 六个触发点 | `persistTabsIfNeeded()` 写新快照 | **写** |

## 四个「为什么这么设计」

新手读代码时最容易产生疑问的地方，集中回答：

**1. 为什么恢复不能走 `appendTab`？**
`appendTab` 是为「运行期加一个 Tab」设计的：`loadViewIfNeeded` + `refreshUI` + 批量插入。批量恢复时这些动作要重复 N 次，而且视图还没上屏时会撞集合视图的计数校验。批量构造数组 + 一次 `reloadData` 才是对的姿势。

**2. 为什么存档存 `selectedIndex` 而不是选中内容的 id？**
关掉 `deduplicateOpenedItems` 后，同一篇文章可以开成多个 Tab。用 id 无法区分是哪一份，用下标才能精确定位。

**3. 为什么恢复过程不写盘？**
`resolver` 返回 `nil` 的条目会被跳过，但它们还在旧存档里。此刻写盘等于把「这次没查到」永久固化成「用户不需要了」。宁可留着旧存档，等用户下次操作时自然覆盖。

**4. 为什么配置只在 `viewDidLoad` 求值一次？**
求值两次就可能前后不一致（读的键和写的键不同），也会让「运行期改开关」产生难以预期的追溯行为。一次求值 + 缓存，语义最清楚。

## 排错速查

| 现象 | 先查这里 |
|---|---|
| 重启后一个 Tab 都没恢复 | ① 启动时 `enable` 调用了吗？② 它是否早于宿主 `viewDidLoad`？③ `resolver` 对某个 id 是否返回了 `nil`？ |
| 恢复了但少了几个 Tab | `resolver` 查不到的条目会被跳过 —— 打印一下存档里的 id 与数据源对得上不上 |
| Tab 数量对，但选中的不是上次那个 | 存档里的 `selectedIndex` 可能因跳过条目而错位；看 `restoredSelectedIndex` 的换算 |
| 关掉开关后 `UserDefaults` 里还有旧数据 | 正常。`disable()` 只关卡不删数据，要清用 `resetPersistedTabs()` |
| 两个窗口互相覆盖对方的 Tab | 两个宿主用了同一个 `persistenceKey`，给各自设不同的 `tabRestorationKey` |
| 启动就崩，报 `Invalid batch updates` | 宿主还没上屏就有代码在开 Tab（启动预热），看 `updateTabBar` 开头那条「未上屏就 reloadData」的保护 |

## 最小接入清单

```swift
// 1. 启动时打开（AppDelegate.didFinishLaunchingWithOptions 里）
PPTabRestoration.enable(resolver: { DataStore.item(withID: $0) })

// 2. 什么都不用做 —— 建窗口、建宿主的代码一行都不用改
```

可选：

```swift
PPTabRestoration.enable(persistenceKey: "MyKey", resolver: { ... })  // 换存档键
host.restoresTabsOnLaunch = false                                    // 某个宿主不恢复
host.tabRestorationKey = "Win-2"                                     // 多窗口各存一份
PPTabRestoration.disable()                                           // 临时关闭（保留存档）
PPTabRestoration.resetPersistedTabs()                                // 清掉存档
```
