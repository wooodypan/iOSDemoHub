//
//  TabDeduplicationTests.swift
//  验证“按内容 ID 去重”：同一个内容已经打开时，不再新建 Tab，而是定位到已有的 Tab。
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

final class TabDeduplicationTests: XCTestCase {

    // 测试期间要自己保住窗口：根控制器只被窗口强持有，窗口一释放视图树就没了。
    private var window: UIWindow?

    // 造一个详情宿主。参数用于选择是否开启去重。
    private func makeHost(deduplicate: Bool) -> DetailHostViewController {
        let host = DetailHostViewController { StubContentViewController() }
        host.deduplicateOpenedItems = deduplicate

        // 放进真实窗口并走一次布局，模拟真实的分栏环境：
        // 这样 Tab 条的 collectionView 会先完成首次加载（此时 0 个 Tab），
        // 后续 insert/delete 的批量更新校验才和线上一致。
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        host.view.layoutIfNeeded()

        return host
    }

    // Tab 数量：直接问宿主的数据源方法（它返回的就是 tabs.count）。
    private func tabCount(of host: DetailHostViewController) -> Int {
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        return host.collectionView(collectionView, numberOfItemsInSection: 0)
    }

    private func article(_ id: String) -> PPContentItem {
        PPContentItem(id: id, title: "Article \(id)", body: "body", category: "Tech")
    }

    // 复现用户报的场景：双击打开 1、双击打开 2，再单击 1。
    // 开启去重后应该还是 2 个 Tab（并且选中态回到 Article 1），而不是开出第三个。
    func test开启去重时不会新建重复Tab() {
        let host = makeHost(deduplicate: true)

        host.openNewTab(article("1"))   // 双击：正式 Tab
        host.openNewTab(article("2"))   // 双击：正式 Tab
        XCTAssertEqual(tabCount(of: host), 2)

        host.openPreview(article("1"))  // 单击已经打开过的 Article 1
        XCTAssertEqual(tabCount(of: host), 2, "已打开的内容应该被定位，而不是开出第三个标签")
    }

    // 对照组：关掉去重开关后，行为应当和改动前一致（会开出第三个 Tab）。
    func test关闭去重时保持原来的VSCode语义() {
        let host = makeHost(deduplicate: false)

        host.openNewTab(article("1"))
        host.openNewTab(article("2"))
        host.openPreview(article("1"))
        XCTAssertEqual(tabCount(of: host), 3, "关掉去重后应当按原语义新建预览 Tab")
    }

    // 去重命中的 Tab 显示的内容就是被点击的那个（说明确实定位到了正确的 Tab）。
    func test去重后定位到的Tab内容正确() {
        let host = makeHost(deduplicate: true)

        host.openNewTab(article("1"))
        host.openNewTab(article("2"))
        host.openPreview(article("1"))

        // 选中项应当切回 Article 1 所在的 Tab（第 0 个）。
        let firstIndexPath = IndexPath(item: 0, section: 0)
        host.collectionView(
            UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout()),
            didSelectItemAt: firstIndexPath
        )
        XCTAssertEqual(tabCount(of: host), 2)
    }

    // 没有内容的新 Tab（item 为 nil）不参与去重，避免空 Tab 被误判成重复。
    func test空Tab不参与去重() {
        let host = makeHost(deduplicate: true)

        host.openNewTab()   // 空 Tab
        host.openNewTab()   // 再开一个空 Tab
        XCTAssertEqual(tabCount(of: host), 2, "空 Tab 没有 id，不应被去重")
    }
}
