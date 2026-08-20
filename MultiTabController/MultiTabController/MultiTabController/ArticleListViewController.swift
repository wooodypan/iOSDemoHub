import UIKit

// MARK: - ArticleListViewController
// 左侧列表。
// 我们用手势区分“单击”和“双击”，从而对应 VS Code 的 Tab 策略：
//   - 单击 = 预览（可复用）
//   - 双击 = 正式打开（不复用）
// iPad/Mac 分屏时通过回调通知父 VC；iPhone 时仍 push 详情页。
class ArticleListViewController: UIViewController {

    private let articles: [Article]
    private let pageTitle: String
    private var tableView: UITableView!

    // iPad/Mac 分屏下：
    // 单击文章 -> 以“预览”方式打开（回调给父 VC 去复用 Preview Tab）
    var onArticleSelected: ((Article) -> Void)?
    // 双击文章 -> 以“正式 Tab”方式打开（不复用，永远新建）
    var onArticleDoubleSelected: ((Article) -> Void)?

    init(articles: [Article], title: String) {
        self.articles = articles
        self.pageTitle = title
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupTableView()
        setupTapGestures()
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
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
        let article = articles[indexPath.row]

        switch DeviceHelper.currentLayout {
        case .iPadOrMac:
            // 分屏：单击 = 预览（交给父 VC 决定复用还是新建 Preview Tab）
            onArticleSelected?(article)
        case .iPhone:
            // iPhone：仍是 push 详情页
            pushDetail(for: article)
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        // 双击只在 iPad/Mac 上用于“正式打开 Tab”；iPhone 忽略
        guard DeviceHelper.currentLayout == .iPadOrMac else { return }
        guard let indexPath = tableView.indexPathForRow(at: gesture.location(in: tableView)) else { return }
        let article = articles[indexPath.row]
        // 双击 = 正式 Tab（不复用）
        onArticleDoubleSelected?(article)
    }

    private func pushDetail(for article: Article) {
        let detailVC = DetailViewController()
        // iPhone 不需要“新Tab/新窗口”按钮（功能降级）
        detailVC.onOpenNewTab = nil
        detailVC.onOpenNewWindow = nil
        detailVC.configure(with: article)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - UITableViewDataSource & Delegate
extension ArticleListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return articles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let article = articles[indexPath.row]
        cell.textLabel?.text = article.title
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // 注意：选中逻辑已改用上面的单击/双击手势处理，这里不再实现 didSelectRowAt，
    // 避免手势与系统选中事件冲突。
}
