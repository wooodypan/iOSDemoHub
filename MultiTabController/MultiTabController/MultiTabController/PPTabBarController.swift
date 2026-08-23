import UIKit

final class PPTabBarController: UIViewController {
    struct ButtonConfiguration {
        let title: String
        let image: UIImage?
        let selectedImage: UIImage?

        init(title: String, image: UIImage?, selectedImage: UIImage? = nil) {
            self.title = title
            self.image = image
            self.selectedImage = selectedImage
        }
    }

    private let viewControllers: [UIViewController]
    private let buttonConfigurations: [ButtonConfiguration]
    private let contentContainerView = UIView()
    private let tabBarContainerView = UIView()
    private let tabBarSeparatorView = UIView()
    private let buttonStackView = UIStackView()

    private var tabButtons: [PPTabBarButton] = []
    private weak var visibleViewController: UIViewController?
    private var tabBarHeightConstraint: NSLayoutConstraint?

    private(set) var selectedIndex: Int
    var onSelectedIndexChanged: ((Int) -> Void)?

    var selectedTintColor: UIColor = {
        if #available(iOS 13.0, *) {
            return .systemBlue
        }
        return .blue
    }() {
        didSet {
            updateButtonStyles()
        }
    }

    var unselectedTintColor: UIColor = UIColor(white: 0.35, alpha: 1.0) {
        didSet {
            updateButtonStyles()
        }
    }

    var tabBarBackgroundColor: UIColor = .white {
        didSet {
            tabBarContainerView.backgroundColor = tabBarBackgroundColor
        }
    }

    var tabBarHeight: CGFloat = 49 {
        didSet {
            tabBarHeightConstraint?.constant = tabBarHeight
        }
    }

    init(
        viewControllers: [UIViewController],
        buttonConfigurations: [ButtonConfiguration],
        initialIndex: Int = 0
    ) {
        precondition(!viewControllers.isEmpty, "PPTabBarController requires at least one view controller.")
        precondition(
            viewControllers.count == buttonConfigurations.count,
            "viewControllers and buttonConfigurations must have the same count."
        )

        self.viewControllers = viewControllers
        self.buttonConfigurations = buttonConfigurations
        self.selectedIndex = min(max(initialIndex, 0), viewControllers.count - 1)
        super.init(nibName: nil, bundle: nil)
        title = buttonConfigurations[self.selectedIndex].title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupViews()
        reloadButtons()
        selectIndex(selectedIndex, notify: false)
    }

    var selectedViewController: UIViewController? {
        guard viewControllers.indices.contains(selectedIndex) else {
            return nil
        }
        return viewControllers[selectedIndex]
    }

    func selectIndex(_ index: Int, notify: Bool = true) {
        guard viewControllers.indices.contains(index) else {
            return
        }

        let nextViewController = viewControllers[index]
        selectedIndex = index
        title = buttonConfigurations[index].title

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

        for (index, configuration) in buttonConfigurations.enumerated() {
            let button = PPTabBarButton()
            button.index = index
            button.apply(
                configuration: configuration,
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
                configuration: buttonConfigurations[index],
                selected: index == selectedIndex,
                selectedTintColor: selectedTintColor,
                unselectedTintColor: unselectedTintColor
            )
        }
    }

    @objc
    private func tabButtonTapped(_ sender: PPTabBarButton) {
        selectIndex(sender.index)
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
        configuration: PPTabBarController.ButtonConfiguration,
        selected: Bool,
        selectedTintColor: UIColor,
        unselectedTintColor: UIColor
    ) {
        let tintColor = selected ? selectedTintColor : unselectedTintColor
        let image = (selected ? configuration.selectedImage : configuration.image) ?? configuration.image

        iconImageView.image = image?.withRenderingMode(.alwaysTemplate)
        iconImageView.tintColor = tintColor
        textLabel.text = configuration.title
        textLabel.textColor = tintColor
    }
}
