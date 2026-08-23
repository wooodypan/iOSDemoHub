import UIKit

// MARK: - WindowManager
// 负责管理新窗口的打开（Mac Catalyst / iPadOS 13+）
// 新窗口打开后，关闭即销毁（不保活）
//
// 对外公开 openNewWindow：外部如果自己实现路由（ArticleOpenRouting），
// 也可以在“新窗口”模式下直接调用这个能力。

public struct WindowManager {

    // 存储新窗口对应的文章（通过 userInfo 传递）
    // 注意：多窗口在 UISceneDelegate 中更优雅，但本工程禁用 SceneDelegate
    // 在 iOS 13 以下或 Catalyst 下，回退到模态弹出

    public static func openNewWindow(article: Article) {
        if #available(iOS 13.0, *) {
            // 优先尝试 UIScene 多窗口（需在 Info.plist 配置 UIApplicationSupportsMultipleScenes）
            // 由于本工程不使用 SceneDelegate，降级为模态弹出
            openAsModal(article: article)
        } else {
            openAsModal(article: article)
        }
    }

    private static func openAsModal(article: Article) {
        // 找到当前最顶层的 ViewController
        guard let topVC = topViewController() else { return }

        let windowVC = NewWindowViewController(article: article)
        let nav = UINavigationController(rootViewController: windowVC)
        nav.modalPresentationStyle = .pageSheet
        topVC.present(nav, animated: true)
    }

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        // 取当前最顶层窗口的根控制器，再层层剥开导航/标签/模态
        let base = base ?? keyWindow()?.rootViewController
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? PPTabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }

    // 获取当前 keyWindow。
    // 传统（非 Scene）生命周期里用 UIApplication.shared.keyWindow；
    // Mac Catalyst 里 keyWindow 不可用，要从 connectedScenes 取窗口，所以按平台区分。
    #if targetEnvironment(macCatalyst)
    private static func keyWindow() -> UIWindow? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first { $0.isKeyWindow }
    }
    #else
    private static func keyWindow() -> UIWindow? {
        return UIApplication.shared.keyWindow
    }
    #endif
}

// MARK: - NewWindowViewController
// 新窗口（模态）内的详情页，关闭即销毁，不保活
class NewWindowViewController: UIViewController {

    private let article: Article
    private let titleLabel = UILabel()
    private let categoryLabel = UILabel()
    private let bodyLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentView = UIView()

    init(article: Article) {
        self.article = article
        super.init(nibName: nil, bundle: nil)
        self.title = article.title
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupCloseButton()
        setupContent()
    }

    private func setupCloseButton() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        // 标记为新窗口
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "🪟 新窗口",
            style: .plain,
            target: nil,
            action: nil
        )
        navigationItem.rightBarButtonItem?.isEnabled = false
    }

    private func setupContent() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        categoryLabel.text = article.category.uppercased()
        categoryLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        categoryLabel.textColor = .systemBlue
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = article.title
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel.text = article.body
        bodyLabel.font = UIFont.systemFont(ofSize: 15)
        bodyLabel.numberOfLines = 0
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        let noteLabel = UILabel()
        noteLabel.text = "⚠️ 此为新窗口模式：关闭后不保留数据"
        noteLabel.font = UIFont.systemFont(ofSize: 13)
        noteLabel.textColor = .systemOrange
        noteLabel.numberOfLines = 0
        noteLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(categoryLabel)
        contentView.addSubview(titleLabel)
        contentView.addSubview(bodyLabel)
        contentView.addSubview(noteLabel)

        NSLayoutConstraint.activate([
            noteLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            noteLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            noteLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            categoryLabel.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 16),
            categoryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            categoryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            titleLabel.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            bodyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            bodyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            bodyLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
        // 注意：dismiss 后此 VC 无强引用持有 → 自动销毁
    }
}
