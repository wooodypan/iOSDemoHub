import UIKit

// MARK: - PPTabBarController
// 自定义标签栏容器（不是系统 UITabBarController）：不读取子控制器的 tabBarItem，
// 而是由外部传入的 [PPTabItem] 定义每一个 Tab 按钮的标题与图标。
//
// 对外公开：集成方既可以直接构造它，也可以用 TabBarBuilder 便捷构造；
// 拿到实例后可配置选中色/背景色/高度、程序化切换 Tab、监听切换事件。
public final class PPTabBarController: UIViewController {

    private let viewControllers: [UIViewController]
    private let items: [PPTabItem]
    private let contentContainerView = UIView()
    private let tabBarContainerView = UIView()
    private let tabBarSeparatorView = UIView()
    private let buttonStackView = UIStackView()

    private var tabButtons: [PPTabBarButton] = []
    private weak var visibleViewController: UIViewController?
    private var tabBarHeightConstraint: NSLayoutConstraint?

    /// 当前选中的下标。程序化切换请用 selectIndex(_:)。
    public private(set) var selectedIndex: Int

    /// Tab 切换回调（用户点击或调用 selectIndex(_:) 都会触发）。
    public var onSelectedIndexChanged: ((Int) -> Void)?

    /// 选中态的图标与文字颜色。
    public var selectedTintColor: UIColor = {
        if #available(iOS 13.0, *) {
            return .systemBlue
        }
        return .blue
    }() {
        didSet {
            updateButtonStyles()
        }
    }

    /// 未选中态的图标与文字颜色。
    public var unselectedTintColor: UIColor = UIColor(white: 0.35, alpha: 1.0) {
        didSet {
            updateButtonStyles()
        }
    }

    /// 标签栏背景色。
    public var tabBarBackgroundColor: UIColor = .white {
        didSet {
            tabBarContainerView.backgroundColor = tabBarBackgroundColor
        }
    }

    /// 标签栏高度（不含底部安全区）。
    public var tabBarHeight: CGFloat = 49 {
        didSet {
            tabBarHeightConstraint?.constant = tabBarHeight
        }
    }

    /// 用"子控制器数组 + Tab 模型数组"构造。
    /// - Parameters:
    ///   - viewControllers: 每个元素对应一个 Tab 的控制器（例如已包好 UINavigationController 的列表页）。
    ///   - items: 与 viewControllers 按索引一一对应的 Tab 模型（标题 + 图标）。
    ///   - initialIndex: 初始选中下标，会被钳制到合法范围内。
    /// - Note: viewControllers 为空、或两个数组长度不一致，都属于调用方的编程错误，
    ///   这里用 precondition 立即中断（早崩优于静默降级）。若长度可能不一致，
    ///   请改用 TabBarBuilder，它会取两者较小的数目对齐。
    public init(
        viewControllers: [UIViewController],
        items: [PPTabItem],
        initialIndex: Int = 0
    ) {
        precondition(!viewControllers.isEmpty, "PPTabBarController requires at least one view controller.")
        precondition(
            viewControllers.count == items.count,
            "viewControllers and items must have the same count."
        )

        self.viewControllers = viewControllers
        self.items = items
        self.selectedIndex = min(max(initialIndex, 0), viewControllers.count - 1)
        super.init(nibName: nil, bundle: nil)
        title = items[self.selectedIndex].title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // public 类里 override 系统 open 方法同样声明 public，与库内其它容器保持一致口径。
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupViews()
        reloadButtons()
        // 初始选中不触发回调（此时外部还没机会设置 onSelectedIndexChanged）。
        setSelectedIndex(selectedIndex, notify: false)
    }

    /// 当前选中的子控制器。
    public var selectedViewController: UIViewController? {
        guard viewControllers.indices.contains(selectedIndex) else {
            return nil
        }
        return viewControllers[selectedIndex]
    }

    /// 程序化切换到指定下标（越界则忽略）。会触发 onSelectedIndexChanged。
    public func selectIndex(_ index: Int) {
        setSelectedIndex(index, notify: true)
    }

    // 真正的切换实现。notify 是内部细节（viewDidLoad 的首次选中不需要通知），故不对外公开。
    private func setSelectedIndex(_ index: Int, notify: Bool) {
        guard viewControllers.indices.contains(index) else {
            return
        }

        let nextViewController = viewControllers[index]
        selectedIndex = index
        title = items[index].title

        if nextViewController.parent == nil {
            addChild(nextViewController)
            nextViewController.view.translatesAutoresizingMaskIntoConstraints = false
            contentContainerView.addSubview(nextViewController.view)
            NSLayoutConstraint.activate([
                nextViewController.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
                nextViewController.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
                nextViewController.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
                nextViewController.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor)
            ])
            nextViewController.didMove(toParent: self)
        }

        visibleViewController?.view.isHidden = true
        nextViewController.view.isHidden = false
        contentContainerView.bringSubviewToFront(nextViewController.view)
        visibleViewController = nextViewController

        updateButtonStyles()

        if notify {
            onSelectedIndexChanged?(index)
        }
    }

    private func setupViews() {
        tabBarContainerView.translatesAutoresizingMaskIntoConstraints = false
        tabBarContainerView.backgroundColor = tabBarBackgroundColor

        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.axis = .horizontal
        buttonStackView.alignment = .fill
        buttonStackView.distribution = .fillEqually
        buttonStackView.spacing = 0

        tabBarSeparatorView.translatesAutoresizingMaskIntoConstraints = false
        tabBarSeparatorView.backgroundColor = UIColor(white: 0.85, alpha: 1.0)

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tabBarContainerView)
        tabBarContainerView.addSubview(buttonStackView)
        view.addSubview(tabBarSeparatorView)
        view.addSubview(contentContainerView)

        let tabBarHeightConstraint = tabBarContainerView.heightAnchor.constraint(equalToConstant: tabBarHeight)
        self.tabBarHeightConstraint = tabBarHeightConstraint

        NSLayoutConstraint.activate([
            contentContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tabBarSeparatorView.topAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
            tabBarSeparatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarSeparatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarSeparatorView.heightAnchor.constraint(equalToConstant: 1),

            tabBarContainerView.topAnchor.constraint(equalTo: tabBarSeparatorView.bottomAnchor),
            tabBarContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            tabBarHeightConstraint,

            buttonStackView.topAnchor.constraint(equalTo: tabBarContainerView.topAnchor),
            buttonStackView.leadingAnchor.constraint(equalTo: tabBarContainerView.leadingAnchor),
            buttonStackView.trailingAnchor.constraint(equalTo: tabBarContainerView.trailingAnchor),
            buttonStackView.bottomAnchor.constraint(equalTo: tabBarContainerView.bottomAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: tabBarSeparatorView.topAnchor)
        ])
    }

    private func reloadButtons() {
        for button in tabButtons {
            button.removeFromSuperview()
        }
        tabButtons.removeAll()

        for (index, item) in items.enumerated() {
            let button = PPTabBarButton()
            button.index = index
            button.apply(
                item: item,
                selected: index == selectedIndex,
                selectedTintColor: selectedTintColor,
                unselectedTintColor: unselectedTintColor
            )
            button.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)
            tabButtons.append(button)
            buttonStackView.addArrangedSubview(button)
        }
    }

    private func updateButtonStyles() {
        for (index, button) in tabButtons.enumerated() {
            button.apply(
                item: items[index],
                selected: index == selectedIndex,
                selectedTintColor: selectedTintColor,
                unselectedTintColor: unselectedTintColor
            )
        }
    }

    @objc
    private func tabButtonTapped(_ sender: PPTabBarButton) {
        setSelectedIndex(sender.index, notify: true)
    }
}

private final class PPTabBarButton: UIControl {
    fileprivate var index: Int = 0

    private let iconImageView = UIImageView()
    private let textLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        textLabel.textAlignment = .center
        textLabel.adjustsFontSizeToFitWidth = true
        textLabel.minimumScaleFactor = 0.8
        textLabel.numberOfLines = 1

        addSubview(iconImageView)
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            iconImageView.widthAnchor.constraint(equalToConstant: 22),
            iconImageView.heightAnchor.constraint(equalToConstant: 22),

            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            textLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 1),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        item: PPTabItem,
        selected: Bool,
        selectedTintColor: UIColor,
        unselectedTintColor: UIColor
    ) {
        let tintColor = selected ? selectedTintColor : unselectedTintColor
        // 没给选中态图标时，选中态复用普通态图标，仅靠 tintColor 区分。
        let image = (selected ? item.selectedImage : item.image) ?? item.image

        iconImageView.image = image?.withRenderingMode(.alwaysTemplate)
        iconImageView.tintColor = tintColor
        textLabel.text = item.title
        textLabel.textColor = tintColor
    }
}
