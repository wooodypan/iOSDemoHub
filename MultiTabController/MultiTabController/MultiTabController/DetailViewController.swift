import UIKit

// MARK: - DetailViewController
// 详情页：展示文章内容，提供“在新Tab打开”和“在新窗口打开”按钮。
// 示例（用两个按钮演示 Bool 属性变化）：
//   点击“标记为已编辑”按钮 -> 本控制器的 Bool 属性 isEdited 变为 true，
//   点击“清除编辑标记”按钮 -> isEdited 变回 false。
//   状态变化时通过 onEditStateChanged 回调通知父控制器（比如把当前 Tab 固定为正式 Tab）。
// 右侧详情页控制器：对外公开，外部可创建、配置并监听其编辑状态。
public class DetailViewController: UIViewController {

    // 由外部注入：在当前详情里点“新 Tab 打开”时回调。
    public var onOpenNewTab: ((PPContentItem) -> Void)?
    // 由外部注入：在当前详情里点“新窗口打开”时回调。
    public var onOpenNewWindow: ((PPContentItem) -> Void)?

    // 当备注输入框内容发生变化时回调：
    //   true  = 用户输入了内容（用于把当前 Tab 固定为正式 Tab）
    //   false = 输入框被清空
    public var onEditStateChanged: ((Bool) -> Void)?

    // 关键 Bool 属性：记录用户是否在备注框里输入过内容。
    // 这是“某个 UIViewController 的某个 Bool 值属性”，输入文字后它就变成 true。
    public var isEdited: Bool = false

    private var currentItem: PPContentItem?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let titleLabel = UILabel()
    private let categoryLabel = UILabel()
    private let bodyLabel = UILabel()
    private let placeholderLabel = UILabel()

    // 编辑状态示例区：一个说明标签 + 两个按钮（标记/清除）
    private let noteLabel = UILabel()
    private var editStackView: UIStackView!

    private var actionStackView: UIStackView!

    // 重写父类的指定初始化方法（与之前一致，保证 DetailViewController() 可用）。
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    // 便捷初始化：可以传入一个内容项（可选），方便外部直接创建并展示内容。
    public convenience init(item: PPContentItem? = nil) {
        self.init(nibName: nil, bundle: nil)
        self.currentItem = item
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // public 类里 override 系统 open 方法必须同样声明 public（编译器强制要求）
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .pp_systemBackground
        setupViews()
        // 视图加载完成后，把 configure 里保存的文章数据渲染到界面上。
        // （作为子控制器创建时，configure 可能在 viewDidLoad 之前被调用，
        //   此时控件还没创建，所以那时只存数据、不碰 UI。）
        applyArticleToUI()
    }

    // MARK: - Setup

    private func setupViews() {
        // ScrollView
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

        // Category
        categoryLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        categoryLabel.textColor = .systemBlue
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false

        // Title
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Body
        bodyLabel.font = UIFont.systemFont(ofSize: 15)
        bodyLabel.numberOfLines = 0
        bodyLabel.textColor = .pp_secondaryLabel
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        // 编辑状态示例说明
        noteLabel.text = "点击下方按钮切换当前 Tab 的“编辑状态”：标记为已编辑后，再点左侧文章会新建 Tab 而非覆盖"
        noteLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        noteLabel.textColor = .pp_secondaryLabel
        noteLabel.numberOfLines = 0
        noteLabel.translatesAutoresizingMaskIntoConstraints = false

        // 两个示例按钮：点击“标记为已编辑” -> isEdited = true；点击“清除编辑标记” -> isEdited = false
        let markEditedButton = makeActionButton(title: "标记为已编辑", systemImage: "checkmark.circle", action: #selector(markAsEdited))
        let clearEditedButton = makeActionButton(title: "清除编辑标记", systemImage: "xmark.circle", action: #selector(clearEdit))
        editStackView = UIStackView(arrangedSubviews: [markEditedButton, clearEditedButton])
        editStackView.axis = .horizontal
        editStackView.spacing = 12
        editStackView.distribution = .fillEqually
        editStackView.translatesAutoresizingMaskIntoConstraints = false

        // Action buttons
        let newTabButton = makeActionButton(title: "在新 Tab 中打开", systemImage: "plus.rectangle.on.rectangle", action: #selector(openNewTab))
        let newWindowButton = makeActionButton(title: "在新窗口中打开", systemImage: "rectangle.on.rectangle.angled", action: #selector(openNewWindow))
        actionStackView = UIStackView(arrangedSubviews: [newTabButton, newWindowButton])
        actionStackView.axis = .horizontal
        actionStackView.spacing = 12
        actionStackView.distribution = .fillEqually
        actionStackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(categoryLabel)
        contentView.addSubview(titleLabel)
        contentView.addSubview(bodyLabel)
        contentView.addSubview(noteLabel)
        contentView.addSubview(editStackView)
        contentView.addSubview(actionStackView)

        NSLayoutConstraint.activate([
            categoryLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            categoryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            categoryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            titleLabel.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            bodyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            bodyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            noteLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 24),
            noteLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            noteLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            editStackView.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 8),
            editStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            editStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            editStackView.heightAnchor.constraint(equalToConstant: 44),

            actionStackView.topAnchor.constraint(equalTo: editStackView.bottomAnchor, constant: 24),
            actionStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            actionStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            actionStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            actionStackView.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Placeholder
        placeholderLabel.text = "← 请从左侧选择文章"
        placeholderLabel.textColor = .pp_tertiaryLabel
        placeholderLabel.font = UIFont.systemFont(ofSize: 18)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        updateVisibility(hasArticle: false)
    }

    private func makeActionButton(title: String, systemImage: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        if #available(iOS 13.0, *) {
            button.setImage(UIImage(systemName: systemImage), for: .normal)
        }
        button.backgroundColor = .systemBlue
        button.tintColor = .white
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func updateVisibility(hasArticle: Bool) {
        placeholderLabel.isHidden = hasArticle
        scrollView.isHidden = !hasArticle
    }

    // MARK: - 编辑状态按钮示例

    // 点击“标记为已编辑”按钮：把 Bool 属性 isEdited 设为 true，并通知父控制器。
    @objc private func markAsEdited() {
        isEdited = true
        onEditStateChanged?(true)
    }

    // 点击“清除编辑标记”按钮：把 Bool 属性 isEdited 设回 false，并通知父控制器。
    @objc private func clearEdit() {
        isEdited = false
        onEditStateChanged?(false)
    }

    // MARK: - Configure

    // 对外公开：用一个内容项配置详情页（数据先行，UI 在视图就绪后渲染，避免提前访问控件闪退）。
    public func configure(with item: PPContentItem) {
        currentItem = item

        // 切换文章时，把编辑状态重置为 false（不触发编辑回调）
        isEdited = false

        // 把数据渲染到界面。关键点：DetailViewController 在作为子控制器创建时，
        // 可能还没触发 viewDidLoad（视图尚未加载），此时直接访问 titleLabel /
        // actionStackView 等控件会闪退（隐式解包的 Optional 为 nil）。
        // 所以这里先只保存数据，真正更新 UI 交给 applyArticleToUI() 处理，
        // 它内部会用 isViewLoaded 判断视图是否已就绪。
        applyArticleToUI()
    }

    // 把保存的文章数据更新到界面控件上。
    // 用 isViewLoaded 守卫：只有视图已经加载（viewDidLoad 跑过、控件已创建），
    // 才真正去设置控件；否则只保存数据，等 viewDidLoad 末尾再调用本方法。
    private func applyArticleToUI() {
        guard isViewLoaded, let item = currentItem else { return }

        categoryLabel.text = item.category.uppercased()
        titleLabel.text = item.title
        bodyLabel.text = item.body
        title = item.title
        updateVisibility(hasArticle: true)

        // iPhone 下，"新Tab"/"新窗口"按钮隐藏（无意义）
        actionStackView.isHidden = (DeviceHelper.currentLayout == .iPhone)
    }

    // MARK: - Actions

    @objc private func openNewTab() {
        guard let item = currentItem else { return }
        onOpenNewTab?(item)
    }

    @objc private func openNewWindow() {
        guard let item = currentItem else { return }
        onOpenNewWindow?(item)
    }
}
