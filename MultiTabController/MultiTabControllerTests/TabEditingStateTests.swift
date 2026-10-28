//
//  TabEditingStateTests.swift
//  验证 Tab 编辑状态 API：谁改了状态、状态存哪儿、预览复用会不会串味、关闭钩子拦不拦得住。
//  视觉部分（灰点 / x 的切换）由单元格负责，这里测的是驱动它的状态机。
//

import XCTest
@testable import MultiTabController

// 测试用的极简内容页：库不认识具体内容，只要满足 PPContentDisplaying 即可。
private final class StubContentViewController: UIViewController, PPContentDisplaying {

    weak var contentHost: PPContentHosting?

    func configure(with item: PPContentItem) {}
}

final class TabEditingStateTests: XCTestCase {

    // 测试期间要自己保住窗口：根控制器只被窗口强持有，窗口一释放视图树就没了。
    private var window: UIWindow?

    private func makeHost() -> DetailHostViewController {
        let host = DetailHostViewController { StubContentViewController() }
        // 必须显式关掉冷启动恢复：测试跑在 Demo App 里，而 Demo 开了全局恢复，
        // 模拟器里会留着上次运行打开的 Tab 快照 —— 不关的话「新宿主」一上来就带着历史 Tab，
        // 断言里的 Tab 数量全对不上（这个坑真踩过）。
        host.restoresTabsOnLaunch = false

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        host.view.layoutIfNeeded()

        return host
    }

    private func tabCount(of host: DetailHostViewController) -> Int {
        host.collectionView(
            UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout()),
            numberOfItemsInSection: 0
        )
    }

    private func article(_ id: String) -> PPContentItem {
        PPContentItem(id: id, title: "Article \(id)", body: "body", category: "Tech")
    }

    // 刚打开的 Tab 一定是「没有未保存修改」的干净状态。
    func test新打开的Tab不是编辑态() {
        let host = makeHost()
        host.openNewTab(article("1"))

        XCTAssertFalse(host.isEditing(forItemID: "1"))
    }

    // 按内容 id 设置 / 取消编辑态。
    func test按内容ID设置编辑态() {
        let host = makeHost()
        host.openNewTab(article("1"))
        host.openNewTab(article("2"))

        host.setEditing(true, forItemID: "2")
        XCTAssertTrue(host.isEditing(forItemID: "2"))
        // 只影响目标 Tab，别的 Tab 不能被带脏。
        XCTAssertFalse(host.isEditing(forItemID: "1"))

        host.setEditing(false, forItemID: "2")
        XCTAssertFalse(host.isEditing(forItemID: "2"))
    }

    // 内容没开成 Tab 时调用不能崩（例如内容已经关掉了，页面才想起来上报）。
    func test对不存在的内容设置编辑态不会崩() {
        let host = makeHost()
        host.openNewTab(article("1"))

        host.setEditing(true, forItemID: "不存在")
        XCTAssertFalse(host.isEditing(forItemID: "不存在"))
        XCTAssertEqual(tabCount(of: host), 1)
    }

    // 内容页通过 contentHost 上报编辑态：这是集成方最常用的路子。
    // 这个用例还顺带守住了协议默认实现那个坑 —— 如果 didChangeEditingState 只写在扩展里，
    // 存在类型调用会静态派发到空实现，宿主这里永远收不到，断言就会失败。
    func test内容页上报编辑态会同步到宿主() {
        let host = makeHost()
        host.openNewTab(article("1"))

        guard let page = host.children.compactMap({ $0 as? StubContentViewController }).first else {
            return XCTFail("宿主应该把内容页 addChild 进来")
        }

        page.contentHost?.contentViewController(page, didChangeEditingState: true)
        XCTAssertTrue(host.isEditing(forItemID: "1"))

        page.contentHost?.contentViewController(page, didChangeEditingState: false)
        XCTAssertFalse(host.isEditing(forItemID: "1"))
    }

    // 「全部保存」场景：一次把所有编辑态清掉。
    func test一次性清空所有编辑态() {
        let host = makeHost()
        host.openNewTab(article("1"))
        host.openNewTab(article("2"))
        host.setEditing(true, forItemID: "1")
        host.setEditing(true, forItemID: "2")

        host.clearAllEditingStates()

        XCTAssertFalse(host.isEditing(forItemID: "1"))
        XCTAssertFalse(host.isEditing(forItemID: "2"))
    }

    // 预览槽位被复用时，载入的是另一份内容，上一份内容留下的灰点必须跟着消失。
    func test预览Tab复用后编辑态复位() {
        let host = makeHost()
        host.openPreview(article("A"))
        host.setEditing(true, forItemID: "A")
        XCTAssertTrue(host.isEditing(forItemID: "A"))

        host.openPreview(article("B"))

        XCTAssertEqual(tabCount(of: host), 1, "预览槽位应该被复用，而不是新开一个")
        XCTAssertFalse(host.isEditing(forItemID: "B"), "新内容不该继承上一份内容的编辑态")
    }

    // 关闭钩子返回 false：这次关闭被取消，Tab 原样留着。
    func test关闭钩子可以拦下未保存的Tab() {
        let host = makeHost()
        host.openNewTab(article("1"))
        host.setEditing(true, forItemID: "1")

        host.shouldCloseTab = { _, isEditing in !isEditing }

        host.closeTab(forItemID: "1")
        XCTAssertEqual(tabCount(of: host), 1, "编辑态下钩子拦住了关闭，Tab 应该还在")

        // 用户确认放弃修改：先清编辑态再关，钩子就放行了。
        host.setEditing(false, forItemID: "1")
        host.closeTab(forItemID: "1")
        XCTAssertEqual(tabCount(of: host), 0)
    }

    // MARK: - 单元格的视觉规则
    // 模拟器里没法注入鼠标悬浮，所以这里只验「没有指针时」的状态：
    // 编辑态只露灰点、非编辑态只露 x（Catalyst 下 x 要等悬浮，故按条件断言）。

    private func makeCell(isEditing: Bool) -> DetailTabCell {
        let cell = DetailTabCell(frame: CGRect(x: 0, y: 0, width: 200, height: 35))
        cell.configure(
            title: "Article 1",
            selected: false,
            isPreview: false,
            isEditing: isEditing,
            selectedBackgroundColor: .white,
            unselectedBackgroundColor: .clear,
            editingIndicatorColor: .gray
        )
        return cell
    }

    func test编辑态只显示灰点不显示x() {
        let cell = makeCell(isEditing: true)

        XCTAssertTrue(cell.isEditingIndicatorVisible, "编辑态应该露出灰色小圆点")
        XCTAssertFalse(cell.isCloseGlyphVisible, "编辑态下 x 要让位给灰点")
    }

    func test非编辑态不显示灰点() {
        let cell = makeCell(isEditing: false)

        XCTAssertFalse(cell.isEditingIndicatorVisible, "非编辑态不该有灰点")
        #if targetEnvironment(macCatalyst)
        XCTAssertFalse(cell.isCloseGlyphVisible, "Catalyst 下 x 要等鼠标悬浮才出现")
        #else
        XCTAssertTrue(cell.isCloseGlyphVisible, "触摸平台没有悬浮，x 一直显示")
        #endif
    }
}
