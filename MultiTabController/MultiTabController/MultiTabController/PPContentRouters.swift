import UIKit

// MARK: - PPContentOpenMode
// 模仿 NewsSplitDemo 的“打开内容”意图枚举。
// 列表页只管发出“想怎么打开”的意图，具体落到哪个设备环境由 router 决定。
//   - preview：预览（单击）。在右侧详情宿主里复用“预览槽位”，对应 VS Code 的 Preview Tab。
//   - newTab ：正式 Tab（双击 / 在详情里点“新Tab打开”）。不复用，永远新建。
//   - newWindow：新窗口打开（Mac Catalyst 多窗口，其它环境降级为新 Tab）。
public enum PPContentOpenMode {
    case preview
    case newTab
    case newWindow
}

// MARK: - PPContentRouting
// 模仿 NewsSplitDemo 的路由协议：把“列表点开内容”从具体展示环境中解耦。
// 列表页只持有这个协议，不再关心自己处于 iPhone 导航栈、还是 iPad 分栏、还是 Mac Catalyst。
public protocol PPContentRouting: AnyObject {
    func open(_ item: PPContentItem, mode: PPContentOpenMode)
}

// MARK: - PPPhoneContentRouter
// iPhone 环境路由：列表在导航栈里，直接 push 内容页即可。
// 内容页由外部注入的工厂提供，本库不含任何内容 UI。
public final class PPPhoneContentRouter: PPContentRouting {
    // 弱引用持有来源 VC，用于拿到它的 navigationController 来 push。
    public weak var sourceViewController: UIViewController?

    // 内容页工厂：每次 push 都造一个新的内容页。
    private let contentViewControllerProvider: PPContentViewControllerProvider

    /// - Parameters:
    ///   - sourceViewController: 发起跳转的列表页，用它的 navigationController 做 push。
    ///   - contentViewControllerProvider: 内容页工厂，每次打开内容调用一次。
    public init(
        sourceViewController: UIViewController,
        contentViewControllerProvider: @escaping PPContentViewControllerProvider
    ) {
        self.sourceViewController = sourceViewController
        self.contentViewControllerProvider = contentViewControllerProvider
    }

    public func open(_ item: PPContentItem, mode: PPContentOpenMode) {
        // 兜底：拿不到导航控制器就不处理。
        guard let navigationController = sourceViewController?.navigationController else {
            return
        }

        switch mode {
        case .preview, .newTab:
            // iPhone 没有”预览/正式”之分，统一 push 一个内容页。
            let detail = contentViewControllerProvider()
            // 不注入 contentHost：iPhone 上没有多 Tab 宿主，
            // 内容页可据此隐藏”新 Tab / 新窗口”这类只在分栏环境下有意义的入口。
            detail.configure(with: item)
            navigationController.pushViewController(detail, animated: true)

        case .newWindow:
            // 新窗口：走 WindowManager 的模态降级实现。
            WindowManager.openNewWindow(item: item)
        }
    }
}

// MARK: - PPSplitContentRouter
// iPad / Mac 分栏环境路由：把“打开内容”转交给右侧的 DetailHostViewController 处理。
// 模仿 NewsSplitDemo 的 SplitArticleRouter，但咱用 WindowManager 替代 WindowLauncher。
public final class PPSplitContentRouter: PPContentRouting {
    // 由 SplitContainerViewController 注入：给定内容项，返回右侧当前可见的详情宿主。
    public var detailHostResolver: ((PPContentItem) -> DetailHostViewController?)?

    // 提供公开的无参初始化器，方便外部自行创建并注入。
    public init() {}

    public func open(_ item: PPContentItem, mode: PPContentOpenMode) {
        switch mode {
        case .preview, .newTab:
            // 交给右侧详情宿主，由它按 VS Code 策略决定复用还是新建。
            detailHostResolver?(item)?.open(item, mode: mode)

        case .newWindow:
            #if targetEnvironment(macCatalyst)
            // Mac Catalyst 支持多窗口，走新窗口。
            WindowManager.openNewWindow(item: item)
            #else
            // 其它环境暂不支持真多窗口，降级为在当前宿主里开新 Tab。
            detailHostResolver?(item)?.openNewTab(item)
            #endif
        }
    }
}
