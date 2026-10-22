//
//  TabRestorationTests.swift
//  验证「冷启动恢复上次的 Tab」：默认关闭、开关生效、单宿主覆盖、以及各种边界。
//
//  几个写测试时必须注意的点：
//   1. 宿主是在 viewDidLoad 里读一次配置的，所以必须先建好宿主、设好 key / resolver / 开关，
//      **再**挂到窗口上（挂窗口就会触发 viewDidLoad）。
//   2. PPTabRestoration 是全局状态，每个用例开头都要复位一次，否则用例之间会互相污染。
//   3. 每个用例用一把独一无二的 UserDefaults 键，跑完删掉，避免读到别的用例的数据。
//

import XCTest
@testable import MultiTabController

// 测试用的极简内容页：库不认识具体内容，只要满足 PPContentDisplaying 即可。
private final class StubContentViewController: UIViewController, PPContentDisplaying {

    // 协议要求：内容页必须 weak 持有宿主，否则会和宿主形成循环引用。
    weak var contentHost: PPContentHosting?
    private(set) var configuredItem: PPContentItem?

    func configure(with item: PPContentItem) {
        configuredItem = item
    }
}

final class TabRestorationTests: XCTestCase {

    // 测试期间要自己保住窗口：根控制器只被窗口强持有，窗口一释放视图树就没了。
    private var windows: [UIWindow] = []

    // MARK: - 造数据

    private func makeKey() -> String {
        return "TabRestorationTests.\(UUID().uuidString)"
    }

    private func article(_ id: String) -> PPContentItem {
        return PPContentItem(id: id, title: "Article \(id)", body: "body", category: "Tech")
    }

    // 用一个字典做 resolver，模拟「按 id 反查业务数据」。
    private func resolver(for items: [PPContentItem]) -> (String) -> PPContentItem? {
        let map = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return { map[$0] }
    }

    // 直接写快照，精确控制顺序、选中下标、预览标记和空 Tab（id 传 nil）。
    // 标 @MainActor 是因为快照类型的 Codable 一致性跟着库的默认隔离走，在非隔离上下文里用会告警。
    @MainActor
    private func seed(_ tabs: [(id: String?, isPreview: Bool)],
                      selected: Int,
                      key: String) throws {
        let snapshot = PPTabRestorationSnapshot(
            version: PPTabRestorationSnapshot.currentVersion,
            tabs: tabs.map { PPTabRestorationSnapshot.Tab(id: $0.id, isPreview: $0.isPreview) },
            selectedIndex: selected
        )
        let data = try JSONEncoder().encode(snapshot)
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - 造宿主

    // 复位全局配置。每个用例开头调一次，不要只依赖清理逻辑 ——
    // 上一个用例中途失败时，下一个也不该继承脏状态。
    @MainActor
    private func prepareGlobals(key: String,
                                enabled: Bool,
                                resolver: ((String) -> PPContentItem?)?) {
        PPTabRestoration.resetConfigurationForTests()
        PPTabRestoration.persistenceKey = key
        PPTabRestoration.contentResolver = resolver
        PPTabRestoration.isEnabled = enabled
    }

    // 建宿主并挂到真实窗口上。configure 闭包在挂窗口之前执行，
    // 所以可以在里面设单宿主覆盖项。
    @MainActor
    private func makeHost(_ configure: (DetailHostViewController) -> Void = { _ in }) -> DetailHostViewController {
        let host = DetailHostViewController { StubContentViewController() }
        configure(host)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        windows.append(window)
        host.view.layoutIfNeeded()

        return host
    }

    // Tab 数量：直接问宿主的数据源方法（它返回的就是 tabs.count）。
    @MainActor
    private func tabCount(of host: DetailHostViewController) -> Int {
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        return host.collectionView(collectionView, numberOfItemsInSection: 0)
    }

    // MARK: - 默认关闭

    @MainActor
    func test默认关闭时不恢复() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        try seed([("a", false), ("b", false)], selected: 0, key: key)
        prepareGlobals(key: key, enabled: false, resolver: resolver(for: [article("a"), article("b")]))

        let host = makeHost()
        XCTAssertEqual(tabCount(of: host), 0, "默认关闭时不应该恢复任何 Tab")
    }

    @MainActor
    func test默认关闭时不写盘() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        prepareGlobals(key: key, enabled: false, resolver: resolver(for: [article("a")]))

        let host = makeHost()
        host.openNewTab(article("a"))
        XCTAssertEqual(tabCount(of: host), 1)
        XCTAssertNil(UserDefaults.standard.data(forKey: key), "开关关着时不应该碰 UserDefaults")
    }

    // MARK: - 基本恢复

    @MainActor
    func test开启后按顺序恢复并选中正确Tab() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let items = [article("1"), article("2"), article("3")]
        try seed([("1", false), ("2", false), ("3", false)], selected: 1, key: key)
        prepareGlobals(key: key, enabled: true, resolver: resolver(for: items))

        let host = makeHost()
        XCTAssertEqual(tabCount(of: host), 3, "三个 Tab 应该原样恢复")
        XCTAssertEqual(host.selectedItem?.id, "2", "应该恢复到上次选中的那一个")
    }

    // 开几个 Tab -> 换一个新宿主读同一把键，验证「保存 + 恢复」整条链路。
    @MainActor
    func test真实操作后重启能恢复() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let items = [article("1"), article("2"), article("3")]
        prepareGlobals(key: key, enabled: true, resolver: resolver(for: items))

        let first = makeHost()
        first.openNewTab(items[0])
        first.openNewTab(items[1])
        first.openNewTab(items[2])
        XCTAssertEqual(tabCount(of: first), 3)

        let second = makeHost()
        XCTAssertEqual(tabCount(of: second), 3, "重启后（换一个宿主）应该恢复 3 个 Tab")
        XCTAssertEqual(second.selectedItem?.id, "3", "上次选中的是最后打开的 Tab")
    }

    @MainActor
    func test恢复保留预览标记() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let items = [article("1"), article("2")]
        try seed([("1", true), ("2", false)], selected: 0, key: key)
        prepareGlobals(key: key, enabled: true, resolver: resolver(for: items))

        let host = makeHost()
        XCTAssertEqual(tabCount(of: host), 2)

        // 预览槽位应该还在：打开一个全新的内容时会复用它，而不是新建第三个 Tab。
        // （如果改用已经打开过的内容，会走去重分支，验证不到预览槽位。）
        host.openPreview(article("9"))
        XCTAssertEqual(tabCount(of: host), 2, "恢复出来的预览 Tab 应该继续占着预览槽位")
    }

    @MainActor
    func test空Tab也能恢复() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        try seed([("1", false), (nil, false)], selected: 1, key: key)
        prepareGlobals(key: key, enabled: true, resolver: resolver(for: [article("1")]))

        let host = makeHost()
        XCTAssertEqual(tabCount(of: host), 2, "空 Tab 也应该被恢复")
        XCTAssertNil(host.selectedItem, "选中的是空 Tab，所以没有内容")
    }

    // MARK: - 内容失效

    @MainActor
    func test内容被删只跳过且不改写存档() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        try seed([("1", false), ("gone", false), ("3", false)], selected: 1, key: key)
        let before = UserDefaults.standard.data(forKey: key)
        // resolver 只认识 1 和 3，"gone" 返回 nil，模拟文章下架。
        prepareGlobals(key: key, enabled: true, resolver: resolver(for: [article("1"), article("3")]))

        let host = makeHost()
        XCTAssertEqual(tabCount(of: host), 2, "查不到的条目只跳过，其余照常恢复")
        XCTAssertEqual(host.selectedItem?.id, "3", "选中的条目失效时回退到相邻的合法 Tab")

        let after = UserDefaults.standard.data(forKey: key)
        XCTAssertEqual(before, after, "恢复过程不应该改写存档（否则下次就没机会再恢复了）")
    }

    @MainActor
    func test没有配置解析器时整份跳过() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        try seed([("1", false)], selected: 0, key: key)
        // 开了开关但没给 resolver：这是合法的中间状态，应该静默不恢复，也不清库。
        prepareGlobals(key: key, enabled: true, resolver: nil)

        let host = makeHost()
        XCTAssertEqual(tabCount(of: host), 0)
        XCTAssertNotNil(UserDefaults.standard.data(forKey: key), "不应该因为没配 resolver 就删掉存档")
    }

    // MARK: - 单宿主覆盖

    @MainActor
    func test单宿主关闭覆盖全局开启() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        try seed([("1", false), ("2", false)], selected: 0, key: key)
        prepareGlobals(key: key, enabled: true, resolver: resolver(for: [article("1"), article("2")]))

        let host = makeHost { host in
            host.restoresTabsOnLaunch = false
        }
        XCTAssertEqual(tabCount(of: host), 0, "单个宿主可以单独关掉恢复")
    }

    @MainActor
    func test单宿主开启覆盖全局关闭() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        try seed([("1", false)], selected: 0, key: key)
        prepareGlobals(key: key, enabled: false, resolver: nil)

        let host = makeHost { host in
            host.restoresTabsOnLaunch = true
            host.tabRestorationResolver = { id in
                id == "1" ? PPContentItem(id: "1", title: "Article 1", body: "body", category: "Tech") : nil
            }
        }
        XCTAssertEqual(tabCount(of: host), 1, "全局关着时，宿主也可以单独打开")
    }

    @MainActor
    func test单宿主key与resolver覆盖全局() throws {
        let globalKey = makeKey()
        let hostKey = makeKey()
        defer {
            UserDefaults.standard.removeObject(forKey: globalKey)
            UserDefaults.standard.removeObject(forKey: hostKey)
        }

        // 全局那份是空的，宿主自己那份有两个。
        try seed([("1", false)], selected: 0, key: globalKey)
        try seed([("1", false), ("2", false)], selected: 1, key: hostKey)
        prepareGlobals(key: globalKey, enabled: true, resolver: resolver(for: [article("1")]))

        let host = makeHost { host in
            host.tabRestorationKey = hostKey
            host.tabRestorationResolver = { id in
                id == "1" || id == "2"
                    ? PPContentItem(id: id, title: "Article \(id)", body: "body", category: "Tech")
                    : nil
            }
        }
        XCTAssertEqual(tabCount(of: host), 2, "有单宿主 key 时应该读宿主自己那份存档")
        XCTAssertEqual(host.selectedItem?.id, "2")
    }

    // MARK: - 边界

    @MainActor
    func test脏数据静默忽略() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        UserDefaults.standard.set(Data("not a snapshot".utf8), forKey: key)
        prepareGlobals(key: key, enabled: true, resolver: resolver(for: [article("1")]))

        let host = makeHost()
        XCTAssertEqual(tabCount(of: host), 0, "解不开的存档当作没有历史，不能崩")
    }

    @MainActor
    func test选中下标越界时回退() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        try seed([("1", false), ("2", false)], selected: 99, key: key)
        prepareGlobals(key: key, enabled: true, resolver: resolver(for: [article("1"), article("2")]))

        let host = makeHost()
        XCTAssertEqual(tabCount(of: host), 2)
        XCTAssertNotNil(host.selectedItem, "下标越界要夹到合法范围，不能没有选中项")
    }

    @MainActor
    func test恢复数量有上限() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let entries: [(id: String?, isPreview: Bool)] = (0..<80).map { ("item-\($0)", false) }
        try seed(entries, selected: 0, key: key)
        // resolver 对任何 id 都能造出内容，模拟「数据还在，但存档异常地长」。
        prepareGlobals(key: key, enabled: true, resolver: { id in
            PPContentItem(id: id, title: id, body: "body", category: "Tech")
        })

        let host = makeHost()
        XCTAssertEqual(tabCount(of: host), PPTabRestoration.maxRestoredTabCount, "超过上限的部分不恢复")
    }

    @MainActor
    func test运行期打开开关不影响已加载宿主() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        try seed([("1", false)], selected: 0, key: key)
        let before = UserDefaults.standard.data(forKey: key)
        prepareGlobals(key: key, enabled: false, resolver: resolver(for: [article("1")]))

        // 先以「关闭」状态加载宿主。
        let host = makeHost()
        // 之后再打开全局开关：不应该追溯这个已经上屏的宿主。
        PPTabRestoration.isEnabled = true

        host.openNewTab(article("2"))
        XCTAssertEqual(tabCount(of: host), 1, "只应该有刚打开的那一个 Tab（既没恢复，也没新建多余 Tab）")

        // 存档应当原封不动：这个宿主在加载时就没启用恢复，之后的操作也不该替它写盘。
        let after = UserDefaults.standard.data(forKey: key)
        XCTAssertEqual(before, after, "运行期打开开关不应该让已加载的宿主开始写盘")
    }

    @MainActor
    func test关闭去重时同内容多Tab原样恢复() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let items = [article("same")]
        prepareGlobals(key: key, enabled: true, resolver: resolver(for: items))

        let first = makeHost { host in
            host.deduplicateOpenedItems = false
        }
        first.openNewTab(items[0])
        first.openNewTab(items[0])
        XCTAssertEqual(tabCount(of: first), 2)

        let second = makeHost { host in
            host.deduplicateOpenedItems = false
        }
        XCTAssertEqual(tabCount(of: second), 2, "关掉去重时同一个内容的多个 Tab 也要原样还原")
    }

    @MainActor
    func test清空接口删除全局快照() throws {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }

        try seed([("1", false)], selected: 0, key: key)
        prepareGlobals(key: key, enabled: true, resolver: resolver(for: [article("1")]))

        PPTabRestoration.resetPersistedTabs()
        XCTAssertNil(UserDefaults.standard.data(forKey: key))
    }

    // 宿主还没上屏（没进窗口）就被预开了 Tab：这是启动阶段恢复/预热的常见姿势。
    // 此时 collectionView 的条数会在布局时一次性同步，若还按增量 insert 去更新，
    // 会被 UIKit 判成「更新前后条数对不上」而崩溃。这条用例守住这个回归。
    @MainActor
    func test未上屏时预开Tab不会崩() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key, enabled: false, resolver: nil)

        // 注意：这里刻意不挂窗口。
        let host = DetailHostViewController { StubContentViewController() }
        host.openNewTab(article("1"))
        host.openNewTab(article("2"))
        host.openNewTab()

        XCTAssertEqual(tabCount(of: host), 3)
    }
}
