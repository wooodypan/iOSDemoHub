import UIKit

// MARK: - ArticleListViewController
// 左侧列表（示例 / Demo）。
// 我们用手势区分“单击”和“双击”，从而对应 VS Code 的 Tab 策略：
//   - 单击 = 预览（可复用）
//   - 双击 = 正式打开（不复用）
// 但列表页不再直接处理“怎么打开”，而是通过 PPContentRouting 协议把意图发出去，
// 具体落到 iPhone 的导航栈还是 iPad 的分栏，由 router 决定（模仿 NewsSplitDemo 的解耦思路）。
// 注意：这是示例控制器，已移到工程宿主层（与 AppDelegate 平级），不属于库本体。
public class ArticleListViewController: UIViewController {

    private let articles: [PPContentItem]
    private let pageTitle: String
    private var tableView: UITableView!

    // 路由协议：列表只发“打开内容”的意图，不关心设备环境。对外公开以便外部注入。
    public var router: PPContentRouting?

    // MARK: 选中行高亮（与右侧选中的 Tab 联动）

    /// 当前高亮行的内容 id（列表里那一行灰底）。
    /// 由外部在右侧切换 Tab 时设置（见 DemoRootFactory 里的联动代码），也可以在点击时自己设置。
    public private(set) var highlightedItemID: String?

    /// 这个列表里是否包含指定内容。右侧切 Tab 时用它判断该高亮哪一个左侧列表。
    public func containsItem(withID id: String) -> Bool {
        return articles.contains(where: { $0.id == id })
    }

    /// 设置 / 清除高亮行（传 `nil` 清除）。
    /// - Parameter scrollToSelection: 目标行不在屏幕内时是否滚动过去。
    ///   用户自己点击时传 false（本来就在眼前）；右侧切 Tab 联动时传 true 更接近 VS Code。
    public func setHighlightedItemID(_ id: String?, scrollToSelection: Bool = false) {
        guard id != highlightedItemID else { return }
        highlightedItemID = id
        // 视图还没加载时只记状态，首次 cellForRowAt 会按 highlightedItemID 上色。
        guard isViewLoaded else { return }
        applyHighlight(scrollToSelection: scrollToSelection)
    }

    // 把高亮状态套用到当前可见的 cell 上；不可见的行等滚动出现时由 cellForRowAt 上色。
    private func applyHighlight(scrollToSelection: Bool) {
        for cell in tableView.visibleCells {
            guard let indexPath = tableView.indexPath(for: cell) else { continue }
            updateHighlightAppearance(of: cell, at: indexPath)
        }

        guard scrollToSelection,
              let indexPath = highlightedIndexPath(),
              tableView.window != nil,
              !(tableView.indexPathsForVisibleRows ?? []).contains(indexPath) else { return }
        tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
    }

    private func highlightedIndexPath() -> IndexPath? {
        guard let id = highlightedItemID,
              let row = articles.firstIndex(where: { $0.id == id }) else { return nil }
        return IndexPath(row: row, section: 0)
    }

    // 选中行用灰底，其余透明（露出 cell 自身的系统背景色）。
    private func updateHighlightAppearance(of cell: UITableViewCell, at indexPath: IndexPath) {
        let isHighlighted = articles[indexPath.row].id == highlightedItemID
        cell.contentView.backgroundColor = isHighlighted ? .pp_selectedRowBackground : .clear
    }

    public init(articles: [PPContentItem], title: String) {
        self.articles = articles
        self.pageTitle = title
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    public required init?(coder: NSCoder) { fatalError() }

    // 库要对外暴露类型，故声明为 public；覆盖系统 open 方法用 internal 亦可，这里统一对外口径。
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .pp_systemBackground
        setupTableView()
        setupTapGestures()
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        // 显式指定表格底色与文字/分割线颜色，让它在深色下也跟系统走：
        // tableView 的默认值本来就是系统色，这里写出来是为了「一眼能看出这个页面适配过深色」，也避免以后换容器时漏掉。
        tableView.backgroundColor = .pp_systemBackground
        tableView.separatorColor = .pp_separator
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: 单击 / 双击手势
    // 用两个 UITapGestureRecognizer 区分单击与双击：
    //   - doubleTap：numberOfTapsRequired = 2
    //   - singleTap：numberOfTapsRequired = 1，且 require(toFail: doubleTap)
    //     意思是“等系统确认不是双击之后”，singleTap 才会触发，
    //     这样双击时不会误触发一次预览。
    private func setupTapGestures() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)

        tableView.addGestureRecognizer(singleTap)
        tableView.addGestureRecognizer(doubleTap)
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard let indexPath = tableView.indexPathForRow(at: gesture.location(in: tableView)) else { return }
        let item = articles[indexPath.row]

        // 先立刻高亮，再发打开意图：右侧 Tab 打开后还会通过回调再同步一次（幂等）。
        setHighlightedItemID(item.id)

        // 把“想怎么打开”的意图交给 router：
        //   iPad/Mac -> 预览（复用预览槽位）
        //   iPhone   -> 直接开新 Tab（push 详情）
        let mode: PPContentOpenMode = (DeviceHelper.currentLayout == .iPadOrMac) ? .preview : .newTab
        router?.open(item, mode: mode)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        // 双击只在 iPad/Mac 上用于“正式打开 Tab”；iPhone 忽略
        guard DeviceHelper.currentLayout == .iPadOrMac else { return }
        guard let indexPath = tableView.indexPathForRow(at: gesture.location(in: tableView)) else { return }
        let item = articles[indexPath.row]
        // 双击 = 正式 Tab（不复用）
        setHighlightedItemID(item.id)
        router?.open(item, mode: .newTab)
    }
}

// MARK: - UITableViewDataSource & Delegate
extension ArticleListViewController: UITableViewDataSource, UITableViewDelegate {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return articles.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let item = articles[indexPath.row]
        // 单元格底色与文字色都显式跟随系统外观（cell 会被复用，所以每次配置都重新赋一遍）。
        cell.backgroundColor = .pp_systemBackground
        cell.textLabel?.textColor = .pp_label
        cell.textLabel?.text = item.title
        cell.accessoryType = .disclosureIndicator
        // cell 会被复用：每次配置都重新按当前高亮状态上色。
        updateHighlightAppearance(of: cell, at: indexPath)
        return cell
    }

    // 注意：选中逻辑已改用上面的单击/双击手势处理，这里不再实现 didSelectRowAt，
    // 避免手势与系统选中事件冲突。
}
