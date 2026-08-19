import UIKit

// MARK: - ArticleListViewController
// 左侧列表，iPad/Mac 分屏时通过 onArticleSelected 回调，iPhone 时 push DetailViewController
class ArticleListViewController: UIViewController {

    private let articles: [Article]
    private let pageTitle: String
    private var tableView: UITableView!

    // iPad/Mac 分屏下，选中文章时通知父 VC
    var onArticleSelected: ((Article) -> Void)?

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

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let article = articles[indexPath.row]

        switch DeviceHelper.currentLayout {
        case .iPadOrMac:
            // 分屏：回调给父 VC 更新右侧详情
            onArticleSelected?(article)
        case .iPhone:
            // iPhone：push DetailViewController
            let detailVC = DetailViewController()
            // iPhone 不需要新Tab/新窗口按钮（或保留，功能降级）
            detailVC.onOpenNewTab = nil
            detailVC.onOpenNewWindow = nil
            detailVC.configure(with: article)
            navigationController?.pushViewController(detailVC, animated: true)
        }
    }
}
