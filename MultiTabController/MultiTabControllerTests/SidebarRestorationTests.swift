//
//  SidebarRestorationTests.swift
//  验证「记住侧栏折叠状态」：折叠 / 展开都能跨启动保持，以及各种开关和边界。
//
//  写测试时要注意：
//   1. 容器是在 viewDidLoad 里读一次配置的，所以必须先建好容器、设好开关和键，再挂窗口。
//   2. PPSidebarRestoration / PPTabRestoration 都是全局状态，每个用例开头都要复位。
//   3. 每个用例用一把独一无二的 UserDefaults 键，跑完删掉，避免读到别的用例的数据。
//

import XCTest
@testable import MultiTabController

// 测试用的极简内容页：库不认识具体内容，只要满足 PPContentDisplaying 即可。
private final class SidebarStubContentViewController: UIViewController, PPContentDisplaying {

    // 协议要求：内容页必须 weak 持有宿主，否则会和宿主形成循环引用。
    weak var contentHost: PPContentHosting?

    func configure(with item: PPContentItem) {}
}

final class SidebarRestorationTests: XCTestCase {

    // 测试期间要自己保住窗口：根控制器只被窗口强持有，窗口一释放视图树就没了。
    private var windows: [UIWindow] = []

    // MARK: - 造数据

    private func makeKey() -> String {
        return "SidebarRestorationTests.\(UUID().uuidString)"
    }

    // 直接往键上写值，模拟「上次运行留下的存档」。
    // 故意不走 saveCollapsed，这样读取那条路径是独立被测的。
    private func seed(_ collapsed: Bool, key: String) {
        UserDefaults.standard.set(collapsed, forKey: key)
    }

    // 读存档。返回 nil 表示这把键上什么都没有。
    private func savedValue(forKey key: String) -> Bool? {
        return UserDefaults.standard.object(forKey: key) as? Bool
    }

    // 复位全局配置。每个用例开头调一次，不要只依赖清理逻辑 ——
    // 上一个用例中途失败时，下一个也不该继承脏状态。
    @MainActor
    private func prepareGlobals(key: String, enabled: Bool = true) {
        PPSidebarRestoration.resetConfigurationForTests()
        PPTabRestoration.resetConfigurationForTests()
        PPSidebarRestoration.persistenceKey = key
        PPSidebarRestoration.isEnabled = enabled
    }

    // 建分栏容器并挂到真实窗口上。configure 在挂窗口之前执行，
    // 用来模拟集成方「上屏前设属性 / 声明启动默认值」。
    @MainActor
    private func makeSplit(_ configure: (SplitContainerViewController) -> Void = { _ in }) -> SplitContainerViewController {
        let split = SplitContainerViewController(
            leftViewController: UIViewController(),
            router: PPSplitContentRouter(),
            contentViewControllerProvider: { SidebarStubContentViewController() }
        )
        // 必须关掉 Tab 冷启动恢复：测试跑在 Demo App 里，AppDelegate 全局开了恢复，
        // 模拟器里留着的 Tab 快照会被新宿主读进来，断言会全崩（这个坑真踩过）。
        split.detailHost.restoresTabsOnLaunch = false
        configure(split)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        window.rootViewController = split
        window.makeKeyAndVisible()
        windows.append(window)
        split.view.layoutIfNeeded()

        return split
    }

    // MARK: - 主链路

    @MainActor
    func test折叠后重启仍是折叠() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key)

        let first = makeSplit()
        XCTAssertTrue(first.isLeftSidebarVisible, "没有存档时默认展开")

        first.isLeftSidebarVisible = false
        XCTAssertFalse(first.isLeftSidebarVisible)
        XCTAssertEqual(savedValue(forKey: key), true, "折叠后应该立刻写盘")

        let second = makeSplit()
        XCTAssertFalse(second.isLeftSidebarVisible, "重启后应该还是折叠")
    }

    @MainActor
    func test展开后重启仍是展开() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key)

        // 先制造一次折叠，再手动展开，验证「新值覆盖旧值」。
        seed(true, key: key)
        let first = makeSplit()
        XCTAssertFalse(first.isLeftSidebarVisible, "先按存档折叠起来")

        first.isLeftSidebarVisible = true
        XCTAssertEqual(savedValue(forKey: key), false, "展开后存档应该改成 false")

        let second = makeSplit()
        XCTAssertTrue(second.isLeftSidebarVisible, "重启后应该还是展开")
    }

    @MainActor
    func test点侧栏按钮也会写盘() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key)

        let first = makeSplit()
        // 侧栏按钮点下去只是发这个回调，容器接住后调 toggleLeftSidebar()。
        first.detailHost.onToggleSidebarRequest?()

        XCTAssertFalse(first.isLeftSidebarVisible, "点一次应该折叠")
        XCTAssertEqual(savedValue(forKey: key), true, "按钮这条路径也要写盘")

        let second = makeSplit()
        XCTAssertFalse(second.isLeftSidebarVisible)
    }

    @MainActor
    func test没有存档时保持展开且不写盘() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key)

        let split = makeSplit()

        XCTAssertTrue(split.isLeftSidebarVisible)
        // 恢复本身不该写盘：首次启动平白多出一个键，等于把「没存过」写成了「存的是展开」。
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }

    // MARK: - 显式设置优先

    @MainActor
    func test加载前显式展开优先于存档() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key)

        // 存档说上次是折叠的，但集成方在挂窗口前要求展开。
        seed(true, key: key)
        let split = makeSplit { $0.isLeftSidebarVisible = true }

        XCTAssertTrue(split.isLeftSidebarVisible, "显式设置优先于存档")
        XCTAssertEqual(savedValue(forKey: key), false, "显式选择要写回存档，别让旧值一直留着")
    }

    @MainActor
    func test加载前显式折叠会被记录下来() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key)

        // 没有存档，集成方要求启动就是折叠的。
        let split = makeSplit { $0.isLeftSidebarVisible = false }

        XCTAssertFalse(split.isLeftSidebarVisible)
        XCTAssertEqual(savedValue(forKey: key), true, "显式折叠也要落盘，下次才能接着折叠")
    }

    // MARK: - 开关

    @MainActor
    func test全局关闭时不读不写() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key, enabled: false)

        seed(true, key: key)
        let split = makeSplit()
        XCTAssertTrue(split.isLeftSidebarVisible, "开关关着时不读存档")

        split.isLeftSidebarVisible = false
        XCTAssertEqual(savedValue(forKey: key), true, "开关关着时不写盘，存档保持原样")
    }

    @MainActor
    func test单实例关闭覆盖全局开启() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key, enabled: true)

        seed(true, key: key)
        let split = makeSplit { $0.restoresSidebarStateOnLaunch = false }

        XCTAssertTrue(split.isLeftSidebarVisible, "单实例关掉后不该读存档")
    }

    @MainActor
    func test单实例key覆盖全局key() {
        let globalKey = makeKey()
        let instanceKey = makeKey()
        defer {
            UserDefaults.standard.removeObject(forKey: globalKey)
            UserDefaults.standard.removeObject(forKey: instanceKey)
        }
        prepareGlobals(key: globalKey)

        seed(false, key: globalKey)     // 全局键：上次是展开
        seed(true, key: instanceKey)    // 实例键：上次是折叠

        let split = makeSplit { $0.sidebarStatePersistenceKey = instanceKey }
        XCTAssertFalse(split.isLeftSidebarVisible, "应该读实例键的存档")

        split.isLeftSidebarVisible = true
        XCTAssertEqual(savedValue(forKey: instanceKey), false, "写的是实例键")
        XCTAssertEqual(savedValue(forKey: globalKey), false, "全局键不该被动过")
    }

    @MainActor
    func test空key不读不写() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key)

        seed(true, key: key)
        let split = makeSplit { $0.sidebarStatePersistenceKey = "" }
        XCTAssertTrue(split.isLeftSidebarVisible, "空键等于没配置，不读存档")

        split.isLeftSidebarVisible = false
        XCTAssertEqual(savedValue(forKey: key), true, "空键也不该往全局键上写")
    }

    // MARK: - 身份标识（多容器隔离）
    //
    // 一个 App 里可能同时存在多个分栏容器（多窗口 / 多场景），默认它们会共用一把键。
    // 第一条用例先把这个「不配身份就会串味」的行为钉住，剩下的验证配了身份之后各存各的。

    @MainActor
    func test两个容器共用全局键会互相覆盖() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key)

        // 第一个窗口折叠：写进全局键。
        let first = makeSplit()
        first.isLeftSidebarVisible = false
        XCTAssertEqual(savedValue(forKey: key), true)

        // 第二个窗口新建，什么都没配，于是读到的是第一个窗口的状态。
        let second = makeSplit()
        XCTAssertFalse(second.isLeftSidebarVisible, "没配身份时两个容器共用一把键，第二个窗口继承了第一个窗口的折叠")

        // 第二个窗口展开，把第一个窗口的存档顶掉。
        second.isLeftSidebarVisible = true
        XCTAssertEqual(savedValue(forKey: key), false, "反过来也成立：后操作的一方覆盖存档")
    }

    @MainActor
    func test不同identity的容器互不干扰() {
        let key = makeKey()
        let keyA = key + ".A"
        let keyB = key + ".B"
        defer {
            [key, keyA, keyB].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        }
        prepareGlobals(key: key)

        // A 窗口折叠：只写带后缀的键，裸键不该被动过。
        let a = makeSplit { $0.sidebarStatePersistenceIdentity = "A" }
        a.isLeftSidebarVisible = false
        XCTAssertEqual(savedValue(forKey: keyA), true, "写的是 A 自己的键")
        XCTAssertNil(UserDefaults.standard.object(forKey: key), "裸键不该被写")

        // B 窗口新建：读不到 A 的存档，仍是默认展开；恢复本身不写盘。
        let b = makeSplit { $0.sidebarStatePersistenceIdentity = "B" }
        XCTAssertTrue(b.isLeftSidebarVisible, "B 不该继承 A 的折叠")
        XCTAssertNil(UserDefaults.standard.object(forKey: keyB), "恢复本身不写盘")

        // 再开一个 A 窗口：读回自己那份。
        let aAgain = makeSplit { $0.sidebarStatePersistenceIdentity = "A" }
        XCTAssertFalse(aAgain.isLeftSidebarVisible, "A 的存档还在")
    }

    @MainActor
    func testidentity同时参与读和写() {
        let key = makeKey()
        let keyA = key + ".A"
        defer {
            [key, keyA].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        }
        prepareGlobals(key: key)

        // 只在带后缀的键上放假存档：读的时候忘了拼后缀，这里就读不到。
        seed(true, key: keyA)
        let split = makeSplit { $0.sidebarStatePersistenceIdentity = "A" }
        XCTAssertFalse(split.isLeftSidebarVisible, "读要拼后缀")

        // 再展开：写的时候同样要拼，不能写回裸键。
        split.isLeftSidebarVisible = true
        XCTAssertEqual(savedValue(forKey: keyA), false, "写也要拼后缀")
        XCTAssertNil(UserDefaults.standard.object(forKey: key), "裸键始终不该被动过")
    }

    @MainActor
    func test空identity等同于未配置() {
        let key = makeKey()
        defer {
            [key, key + "."].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        }
        prepareGlobals(key: key)

        seed(true, key: key)
        let split = makeSplit { $0.sidebarStatePersistenceIdentity = "" }
        XCTAssertFalse(split.isLeftSidebarVisible, "空身份不拼后缀，行为和不设一样")

        split.isLeftSidebarVisible = true
        XCTAssertEqual(savedValue(forKey: key), false, "写回裸键")
        XCTAssertNil(UserDefaults.standard.object(forKey: key + "."), "不该拼出只有一个点的怪键")
    }

    @MainActor
    func testidentity拼在实例key之后() {
        let globalKey = makeKey()
        let instanceKey = makeKey()
        let finalKey = instanceKey + ".w1"
        defer {
            [globalKey, instanceKey, finalKey].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        }
        prepareGlobals(key: globalKey)

        seed(true, key: finalKey)
        let split = makeSplit {
            $0.sidebarStatePersistenceKey = instanceKey
            $0.sidebarStatePersistenceIdentity = "w1"
        }
        XCTAssertFalse(split.isLeftSidebarVisible, "后缀拼在实例键后面，不是拼在全局键后面")

        split.isLeftSidebarVisible = true
        XCTAssertEqual(savedValue(forKey: finalKey), false)
        XCTAssertNil(UserDefaults.standard.object(forKey: instanceKey), "实例裸键不该被动过")
        XCTAssertNil(UserDefaults.standard.object(forKey: globalKey), "全局键也不该被动过")
    }

    @MainActor
    func test加载前显式设置写到带后缀的键() {
        let key = makeKey()
        let keyA = key + ".A"
        defer {
            [key, keyA].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        }
        prepareGlobals(key: key)

        // 上次是展开，这次业务要求默认折叠：显式设置优先，并把新值写回存档。
        seed(false, key: keyA)
        let split = makeSplit {
            $0.sidebarStatePersistenceIdentity = "A"
            $0.isLeftSidebarVisible = false
        }

        XCTAssertFalse(split.isLeftSidebarVisible, "以显式设置为准")
        XCTAssertEqual(savedValue(forKey: keyA), true, "写回也走带后缀的键")
        XCTAssertNil(UserDefaults.standard.object(forKey: key), "裸键不该被动过")
    }

    @MainActor
    func test实例key为空时identity也不生效() {
        let key = makeKey()
        defer {
            [key, ".A"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        }
        prepareGlobals(key: key)

        seed(true, key: key)
        let split = makeSplit {
            $0.sidebarStatePersistenceKey = ""
            $0.sidebarStatePersistenceIdentity = "A"
        }
        XCTAssertTrue(split.isLeftSidebarVisible, "基础键为空等于关掉这个能力，身份救不回来")

        split.isLeftSidebarVisible = false
        XCTAssertEqual(savedValue(forKey: key), true, "全局裸键没被动过")
        XCTAssertNil(UserDefaults.standard.object(forKey: ".A"), "也不该拼出一个只有后缀的键")
    }

    @MainActor
    func testresetPersistedState按identity清数据() {
        let key = makeKey()
        let keyA = key + ".A"
        let keyB = key + ".B"
        defer {
            [key, keyA, keyB].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        }
        prepareGlobals(key: key)

        let a = makeSplit { $0.sidebarStatePersistenceIdentity = "A" }
        a.isLeftSidebarVisible = false
        XCTAssertEqual(savedValue(forKey: keyA), true)
        seed(true, key: keyB)

        PPSidebarRestoration.resetPersistedState(identity: "A")

        XCTAssertNil(UserDefaults.standard.object(forKey: keyA), "只清指定身份的那把键")
        XCTAssertEqual(savedValue(forKey: keyB), true, "别的窗口不受影响")
        XCTAssertFalse(a.isLeftSidebarVisible, "只清数据，不动界面")
    }

    // MARK: - 数据与生命周期边界

    @MainActor
    func test脏数据静默忽略() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key)

        // 存档被别的代码 / 旧版本写坏了。
        UserDefaults.standard.set("not a bool", forKey: key)
        let split = makeSplit()

        XCTAssertTrue(split.isLeftSidebarVisible, "读不出来就当没有历史，按默认展开")
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "not a bool", "不主动清坏数据")
    }

    @MainActor
    func testresetPersistedState只清数据不改当前状态() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key)

        let split = makeSplit()
        split.isLeftSidebarVisible = false
        XCTAssertEqual(savedValue(forKey: key), true)

        PPSidebarRestoration.resetPersistedState()

        XCTAssertNil(UserDefaults.standard.object(forKey: key), "存档应该被删掉")
        XCTAssertFalse(split.isLeftSidebarVisible, "只清数据，不动界面上的侧栏")
    }

    @MainActor
    func test运行期改开关不追溯已加载容器() {
        let key = makeKey()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        prepareGlobals(key: key, enabled: true)

        let split = makeSplit()
        // 容器加载完之后再关开关：它已经求值过了，会继续按当初的配置写盘。
        PPSidebarRestoration.isEnabled = false
        split.isLeftSidebarVisible = false

        XCTAssertEqual(savedValue(forKey: key), true, "已加载容器仍按首次求值的配置写盘")

        // 之后新建的容器才吃新配置。
        let later = makeSplit()
        XCTAssertTrue(later.isLeftSidebarVisible, "新容器不再读存档")
    }
}
