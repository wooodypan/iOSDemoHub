import Foundation

// MARK: - PPTabRestoration
//
// 冷启动恢复上次打开的 Tab 的全局开关。目标是「外部一行代码接入」：
//
//     PPTabRestoration.enable { DataStore.item(withID: $0) }
//
// 默认关闭。没显式打开时，库完全不读 UserDefaults、不建任何 Tab，
// 表现和没有这个能力时一模一样 —— 升级上来的老项目不会突然多出几个标签页。
//
// 为什么是「全局开关 + 单宿主覆盖」？
//   启动配置只写一处最省事；但多窗口、多数据源的 App 里总有个别宿主不该跟着走，
//   所以 DetailHostViewController 上还留了三个默认 nil 的覆盖项（见那边的注释）。
//
// 求值时机：每个宿主在自己的 viewDidLoad 里读一次配置，之后不再变。
//   也就是说运行期改这里的值，只影响之后才首次加载的宿主，不会追溯已经上屏的宿主。
//   中途把历史 Tab 塞进一个开着的宿主，等于替换用户当前的工作现场，
//   还要处理和现有 Tab、预览槽位的合并，收益远小于风险。
@MainActor
public enum PPTabRestoration {

    // MARK: - 开关

    /// 是否启用冷启动恢复。默认 `false`。
    ///
    /// 这个属性**故意没有 didSet**：赋值本身不读盘、不写盘、也不通知已有宿主。
    /// 它只是一份「给之后首次加载的宿主看的配置」，没有副作用需要处理，
    /// 所以也不需要「新旧值相同就跳过」这种优化。
    ///
    /// - Important: 请在启动时（建根控制器之前）设置。宿主是在 viewDidLoad 里读它的，
    ///   之后才设置不会补做恢复。
    public static var isEnabled: Bool = false

    // MARK: - 配置

    // enable / reset 共用同一个默认键，避免两处手写字符串写歪。
    private static let defaultPersistenceKey = "PPTabRestoration"

    /// 保存 Tab 快照用的 UserDefaults 键。默认 `"PPTabRestoration"`。
    ///
    /// 和 `PPAppearance.persistenceKey` 不同，这里不接受 nil：这个能力的本质就是持久化，
    /// 没有「只在内存里恢复」的形态。关闭开关时这把键完全不生效（不读也不写），
    /// 所以留着默认值不会污染 UserDefaults。
    ///
    /// - Important: 要在宿主 view 加载之前设置。运行期改键只影响之后首次加载的宿主，
    ///   已经加载过的宿主会继续用它当初读到的那把键。
    public static var persistenceKey: String = defaultPersistenceKey

    /// 把存档里的内容 id 还原成 `PPContentItem`。默认 nil（等于没配置，什么都不会恢复）。
    ///
    /// - 返回 nil 表示「这条内容确实不存在了」（文章被删、业务 id 规则变了）。
    ///   库会跳过这一条，但**不会**因此改写存档：一次临时的数据未就绪，
    ///   不应该把用户的历史永久删掉。等下一次用户真正操作 Tab 时才会写入新快照。
    /// - 这个闭包在主线程、宿主 viewDidLoad 期间被逐条调用。请做成 O(1) 的本地查表，
    ///   不要在这里发网络请求或做大量 IO，否则会拖慢启动。
    /// - 它是全局静态属性，会被一直持有；闭包捕获外部对象时请用 weak 避免泄漏。
    public static var contentResolver: ((String) -> PPContentItem?)?

    // MARK: - 一行接入

    /// 用默认键打开恢复。
    ///
    /// 这是最常见的接入方式，放在 `application(_:didFinishLaunchingWithOptions:)` 里、
    /// 建窗口之前即可。重复调用是幂等的：只是把同样的配置再写一遍，不会重复读盘。
    public static func enable(resolver: @escaping (String) -> PPContentItem?) {
        persistenceKey = defaultPersistenceKey
        contentResolver = resolver
        // 最后再打开开关：保证任何读到 isEnabled == true 的地方，另外两项都已经就位。
        isEnabled = true
    }

    /// 用自定义键打开恢复（多窗口 / 一个 App 里要存多份时用）。
    /// - Important: 空字符串会被当作「未配置」，该宿主既不恢复也不保存。
    public static func enable(persistenceKey: String,
                              resolver: @escaping (String) -> PPContentItem?) {
        self.persistenceKey = persistenceKey
        contentResolver = resolver
        isEnabled = true
    }

    /// 关闭恢复。**不会**删除已经存下的快照 —— 临时关掉不该毁掉用户状态。
    /// 要连数据一起清掉，用 `resetPersistedTabs()`。
    public static func disable() {
        isEnabled = false
    }

    /// 清掉全局键下的快照（给「恢复默认设置 / 清除浏览记录」这类入口用）。
    ///
    /// - Important: 只清存档，**不会关闭当前已经打开的 Tab**。
    ///   如果此时宿主还活着，用户下一次操作 Tab 会立刻把当前状态重新写回去。
    ///   想真正清干净，请在根控制器加载之前调用，或者同时关掉相关宿主。
    /// - 只清 `persistenceKey` 这一把键；宿主用 `tabRestorationKey` 自定义的键要自己清。
    public static func resetPersistedTabs() {
        removeSnapshot(forKey: persistenceKey)
    }

    // MARK: - 内部：存档读写
    //
    // 全部收在这里，宿主不直接碰 UserDefaults；以后要换存储（文件 / 数据库 / App Group）只改这一处。
    // 刻意只提供「整份快照一次读写」，不做增量 —— 一次写完才能保证
    // 「Tab 列表 + 选中项 + 预览标记」是同一时刻的状态，不会读到半新半旧的组合。

    /// 最多恢复多少个 Tab。防的是「存档被改坏 / 旧版本遗留」时一次拉起成百上千个控制器。
    /// 属于实现层的安全阀，不是业务配置，所以不对外公开。
    static let maxRestoredTabCount = 50

    static func loadSnapshot(forKey key: String) -> PPTabRestorationSnapshot? {
        guard !key.isEmpty,
              let data = UserDefaults.standard.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(PPTabRestorationSnapshot.self, from: data),
              snapshot.version == PPTabRestorationSnapshot.currentVersion else {
            // 没存过 / 解不开 / 版本对不上：都当作「没有历史」，静默忽略。
            // 这里不主动清坏数据：万一只是这次读取异常，下次还有机会；
            // 真正的覆盖发生在用户下一次操作 Tab 时。
            return nil
        }
        return snapshot
    }

    static func saveSnapshot(_ snapshot: PPTabRestorationSnapshot, forKey key: String) {
        guard !key.isEmpty, let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func removeSnapshot(forKey key: String) {
        guard !key.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - 内部：单测支持

    /// 仅供单测：把全局配置恢复成默认值，避免用例之间互相污染。
    /// 做成一个方法而不是让每个用例自己逐个赋值，是为了以后新增字段时不会漏。
    static func resetConfigurationForTests() {
        isEnabled = false
        persistenceKey = defaultPersistenceKey
        contentResolver = nil
    }
}

// MARK: - PPTabRestorationSnapshot
//
// 库内部的存档结构，不属于公开 API：集成方只需要提供 resolver，不需要知道存了什么。
//
// 为什么用 Codable + 单个 Data，而不是拆成三个键（ids / selected / previews）？
//   三个键分开写，读取时可能拿到「新的 ids + 旧的 selected」这种撕裂状态；
//   一个 JSON 一次写入，至少保证同一份快照内部是自洽的。
struct PPTabRestorationSnapshot: Codable {

    struct Tab: Codable {
        /// 内容 id（不是 Tab 自己的 UUID —— 那个每次启动都会变，没法用来恢复）。
        /// nil 表示这是一个「空 Tab」（标题显示为 "New Tab"），恢复时照常建出来。
        let id: String?
        /// 这个 Tab 是不是预览 Tab；恢复后仍然占着预览槽位。
        let isPreview: Bool
    }

    /// 存档格式版本。以后字段变了就 +1，旧存档会被当成「没有历史」忽略，不会崩。
    static let currentVersion = 1

    let version: Int
    /// 按 Tab 条上的顺序保存，包含空 Tab。
    let tabs: [Tab]
    /// 选中的是第几个 Tab（下标，不是内容 id）：关掉去重后同一个内容可以开成多个 Tab，
    /// 用 id 无法区分是哪一份。
    let selectedIndex: Int
}
