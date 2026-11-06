import Foundation

// MARK: - PPSidebarRestoration
//
// 记住分栏容器左侧栏是收起还是展开，下次冷启动自动还原。
//
// 默认开启，集成方不用写任何代码：用户在界面上收起侧栏，杀掉 App 再打开，侧栏仍然是收起的。
// 想关掉就设 `PPSidebarRestoration.isEnabled = false`，并且要在根控制器创建之前设。
//
// 为什么这个默认开、而 PPTabRestoration 默认关？
//   Tab 恢复会往界面里塞回上次打开的内容，属于「改变首屏」的能力，误开代价大；
//   侧栏折叠只是把用户自己摆好的布局摆回去，不改内容，风险小得多。
//
// 只存「折叠 / 展开」一个 Bool，不存左栏宽度。
//   宽度是拖动调出来的像素值，跟屏幕尺寸强相关，换设备或转屏后原样套回去往往不合适。
//
// 求值时机：每个分栏容器在自己的 viewDidLoad 里读一次配置，之后不再变。
//   运行期改这里的值，只影响之后才首次加载的容器，不会追溯已经上屏的容器。
@MainActor
public enum PPSidebarRestoration {

    // MARK: - 开关

    /// 是否启用侧栏状态持久化。默认 `true`。
    ///
    /// 这个属性故意没有 didSet：它只是一份「给之后首次加载的容器看的配置」，
    /// 赋值本身不读盘、不写盘，也不通知已经存在的容器。
    ///
    /// - Important: 请在根控制器创建之前设置。容器是在 viewDidLoad 里读它的，
    ///   之后才设置不会补做恢复。
    public static var isEnabled: Bool = true

    // MARK: - 配置

    // reset 和默认值共用同一个字符串，避免两处手写写歪。
    private static let defaultPersistenceKey = "PPSidebarRestoration"

    /// 保存折叠状态用的 UserDefaults 键。默认 `"PPSidebarRestoration"`。
    ///
    /// 不接受 nil：这个能力的本质就是持久化，没有「只在内存里恢复」的形态，关闭请用 `isEnabled`。
    /// 空字符串按「未配置」处理，容器既不读也不写。
    ///
    /// - Important: 要在容器 view 加载之前设置。运行期改键只影响之后首次加载的容器，
    ///   已经加载过的容器会继续用它当初读到的那把键。
    public static var persistenceKey: String = defaultPersistenceKey

    // MARK: - 清数据

    /// 清掉全局键下的存档，给「恢复默认布局 / 重置设置」这类入口用。
    ///
    /// - Important: 只删存档，不会改当前界面上的侧栏状态。
    ///   容器还活着时，用户下一次展开 / 折叠会立刻把新状态写回去。
    ///   想彻底清干净，请在根控制器加载之前调用。
    /// - 只清 `persistenceKey` 这一把**裸键**；容器配了 `sidebarStatePersistenceIdentity`
    ///   或 `sidebarStatePersistenceKey` 的，存档在别的键上，请用 `resetPersistedState(identity:)` 或自己清。
    public static func resetPersistedState() {
        removePersistedState(forKey: persistenceKey)
    }

    /// 清掉「全局键 + 身份后缀」下的存档，对应容器设了 `sidebarStatePersistenceIdentity` 的场景。
    ///
    /// 一个 App 开了多个窗口时，每个窗口的存档在各自的带后缀键上；这个入口只清你指定的那一个，
    /// 别的窗口不受影响。
    ///
    /// - Parameter identity: 容器上设的那个身份标识。传空字符串等同于 `resetPersistedState()`（不加后缀）。
    /// - Important: 和 `resetPersistedState()` 一样，只删存档，不改当前界面。
    /// - Note: 这里的 base 固定是 `persistenceKey`。容器用 `sidebarStatePersistenceKey` 换过基础键的，
    ///   本方法清不到，需要自己按拼好的键删。
    public static func resetPersistedState(identity: String) {
        guard let key = resolvedKey(base: persistenceKey, identity: identity) else { return }
        removePersistedState(forKey: key)
    }

    // MARK: - 内部：存档读写
    //
    // 全部收在这里，容器不直接碰 UserDefaults；以后要换存储（文件 / 数据库 / App Group）只改这一处。

    /// 把「基础键 + 容器身份」拼成真正落盘的键。返回 `nil` 表示这次不持久化。
    ///
    /// 规则只有三条，容器和 `resetPersistedState(identity:)` 都走这里，
    /// 免得出现「读的时候拼了、写的时候忘了拼」这种一半对一半错的错位：
    ///   - 基础键为空 → 不持久化。空键的既有语义就是「不读不写」，配了身份也救不回来。
    ///   - 身份为 `nil` 或空字符串 → 原样用基础键，和没有这个能力时逐字节一致，老存档能直接读到。
    ///   - 两者都有值 → `基础键.身份`，分隔符用点，和 README 里手拼的写法保持一致。
    static func resolvedKey(base: String, identity: String?) -> String? {
        guard !base.isEmpty else { return nil }
        guard let identity = identity, !identity.isEmpty else { return base }
        return base + "." + identity
    }

    /// 读回上次的折叠状态。返回 nil 表示「没有历史」或者「存档坏了」。
    ///
    /// 这里必须用 object(forKey:) 再桥接成 Bool，不能用 bool(forKey:)：
    /// 后者在键不存在时也返回 false，会把「从没存过」和「上次是展开」混成同一个结果，
    /// 容器就没法判断该不该用存档覆盖默认状态了。
    static func loadCollapsed(forKey key: String) -> Bool? {
        guard !key.isEmpty else { return nil }
        // 脏数据（字符串、Data 之类）桥接不成 Bool 时得到 nil，静默当作没有历史。
        // 不主动清坏数据：万一只是这次读取异常，下次还有机会。
        return UserDefaults.standard.object(forKey: key) as? Bool
    }

    static func saveCollapsed(_ collapsed: Bool, forKey key: String) {
        guard !key.isEmpty else { return }
        UserDefaults.standard.set(collapsed, forKey: key)
    }

    static func removePersistedState(forKey key: String) {
        guard !key.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - 内部：单测支持

    /// 仅供单测：把全局配置恢复成默认值，避免用例之间互相污染。
    /// 做成一个方法而不是让每个用例自己逐个赋值，是为了以后新增字段时不会漏。
    static func resetConfigurationForTests() {
        isEnabled = true
        persistenceKey = defaultPersistenceKey
    }
}
