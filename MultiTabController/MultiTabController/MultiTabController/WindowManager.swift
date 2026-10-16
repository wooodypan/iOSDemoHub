import UIKit

// MARK: - WindowManager
// 负责管理新窗口的打开（Mac Catalyst / iPadOS 13+）
// 新窗口打开后，关闭即销毁（不保活）
//
// 关于生命周期兼容（本库两种都支持）：
//   - UIScene 生命周期（iOS 27 SDK 起 Apple 强制要求，见 TN3187）：窗口归 UIWindowScene 管；
//   - 传统 AppDelegate 生命周期：窗口归 AppDelegate.window 管。
//   取窗口这件事统一交给 AppLifecycle.activeWindow，所以下面的代码不用区分是哪一种。
//
// 关于“真·多窗口”：
//   只有 App 采用了 Scene 生命周期、且 Info.plist 里 UIApplicationSupportsMultipleScenes = YES 时，
//   系统才允许开第二个窗口（用 AppLifecycle.supportsMultipleScenes 判断）。
//   本类刻意不碰场景 API，而是统一降级成「模态弹出」：这样两种生命周期下观感一致，
//   也不会替宿主擅自决定“新场景里应该显示什么”。
//   要做真多窗口，宿主自己实现 PPContentRouting，在 .newWindow 分支里调用
//   UIApplication.requestSceneSessionActivation(_:userActivity:options:errorHandler:)——
//   库已经把“路由”做成了协议，这是最合适的扩展点。
//
// 对外公开 openNewWindow：外部如果自己实现路由（PPContentRouting），
// 也可以在“新窗口”模式下直接调用这个能力。

public struct WindowManager {

    /// 打开一个新的“窗口”（当前实现是模态弹出的降级方案）。
    /// 行为在 UIScene 生命周期与传统 AppDelegate 生命周期下完全一致。
    public static func openNewWindow(item: PPContentItem) {
        // 统一走模态：不依赖 scene / 不依赖 AppDelegate 的窗口属性，两条生命周期都能用。
        openAsModal(item: item)
    }

    private static func openAsModal(item: PPContentItem) {
        // 找到当前最顶层的 ViewController
        guard let topVC = topViewController() else { return }

        let windowVC = NewWindowViewController(item: item)
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

    // 获取当前 keyWindow：统一交给 AppLifecycle.activeWindow。
    // 内部已经按「Scene 生命周期优先、传统生命周期兜底」的顺序找过，
    // 所以这里不用再按平台（Catalyst / iOS）或生命周期分叉。
    private static func keyWindow() -> UIWindow? {
        return AppLifecycle.activeWindow
    }
}

// MARK: - NewWindowViewController
// 新窗口（模态）内的详情页，关闭即销毁，不保活
class NewWindowViewController: UIViewController {

    private let item: PPContentItem
    private let titleLabel = UILabel()
    private let categoryLabel = UILabel()
    private let bodyLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentView = UIView()

    init(item: PPContentItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
        self.title = item.title
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .pp_systemBackground
        setupCloseButton()
        setupContent()
    }

    private func setupCloseButton() {
        // iOS 13+ 用 .close（显示小 X 图标）；iOS 12 没有 .close，回退到 .done（显示"完成"）。
        let closeButtonItem: UIBarButtonItem
        if #available(iOS 13.0, *) {
            closeButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(closeTapped)
            )
        } else {
            closeButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(closeTapped)
            )
        }
        navigationItem.leftBarButtonItem = closeButtonItem
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

        categoryLabel.text = item.category.uppercased()
        categoryLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        categoryLabel.textColor = .systemBlue
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = item.title
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        // 文字色显式跟随系统外观，避免深色下「黑字黑底」。
        titleLabel.textColor = .pp_label
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel.text = item.body
        bodyLabel.font = UIFont.systemFont(ofSize: 15)
        bodyLabel.numberOfLines = 0
        bodyLabel.textColor = .pp_secondaryLabel
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
