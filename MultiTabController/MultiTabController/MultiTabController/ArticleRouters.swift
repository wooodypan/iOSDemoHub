import UIKit

// MARK: - ArticleOpenMode
// 模仿 NewsSplitDemo 的“打开文章”意图枚举。
// 列表页只管发出“想怎么打开”的意图，具体落到哪个设备环境由 router 决定。
//   - preview：预览（单击）。在右侧详情宿主里复用“预览槽位”，对应 VS Code 的 Preview Tab。
//   - newTab ：正式 Tab（双击 / 在详情里点“新Tab打开”）。不复用，永远新建。
//   - newWindow：新窗口打开（Mac Catalyst 多窗口，其它环境降级为新 Tab）。
enum ArticleOpenMode {
    case preview
    case newTab
    case newWindow
}

// MARK: - ArticleOpenRouting
// 模仿 NewsSplitDemo 的路由协议：把“列表点开文章”从具体展示环境中解耦。
// 列表页只持有这个协议，不再关心自己处于 iPhone 导航栈、还是 iPad 分栏、还是 Mac Catalyst。
protocol ArticleOpenRouting: AnyObject {
    func openArticle(_ item: Article, mode: ArticleOpenMode)
}

// MARK: - PhoneArticleRouter
// iPhone 环境路由：列表在导航栈里，直接 push 详情页即可。
// 模仿 NewsSplitDemo 的 PhoneArticleRouter，但咱用 WindowManager 处理新窗口（无 WindowLauncher 依赖）。
final class PhoneArticleRouter: ArticleOpenRouting {
    // 弱引用持有来源 VC，用于拿到它的 navigationController 来 push。
    weak var sourceViewController: UIViewController?

    init(sourceViewController: UIViewController) {
        self.sourceViewController = sourceViewController
    }

    func openArticle(_ item: Article, mode: ArticleOpenMode) {
        // 兜底：拿不到导航控制器就不处理。
        guard let navigationController = sourceViewController?.navigationController else {
            return
        }

        switch mode {
        case .preview, .newTab:
            // iPhone 没有“预览/正式”之分，统一 push 一个详情页。
            let detail = DetailViewController()
            detail.configure(with: item)
            // iPhone 上“新Tab/新窗口”按钮无意义，关掉。
            detail.onOpenNewTab = nil
            detail.onOpenNewWindow = nil
            navigationController.pushViewController(detail, animated: true)

        case .newWindow:
            // 新窗口：走 WindowManager 的模态降级实现。
            WindowManager.openNewWindow(article: item)
        }
    }
}

// MARK: - SplitArticleRouter
// iPad / Mac 分栏环境路由：把“打开文章”转交给右侧的 DetailHostViewController 处理。
// 模仿 NewsSplitDemo 的 SplitArticleRouter，但咱用 WindowManager 替代 WindowLauncher。
final class SplitArticleRouter: ArticleOpenRouting {
    // 由 SplitContainerViewController 注入：给定文章，返回右侧当前可见的详情宿主。
    var detailHostResolver: ((Article) -> DetailHostViewController?)?

    func openArticle(_ item: Article, mode: ArticleOpenMode) {
        switch mode {
        case .preview, .newTab:
            // 交给右侧详情宿主，由它按 VS Code 策略决定复用还是新建。
            detailHostResolver?(item)?.openArticle(item, mode: mode)

        case .newWindow:
            #if targetEnvironment(macCatalyst)
            // Mac Catalyst 支持多窗口，走新窗口。
            WindowManager.openNewWindow(article: item)
            #else
            // 其它环境暂不支持真多窗口，降级为在当前宿主里开新 Tab。
            detailHostResolver?(item)?.openNewTab(item)
            #endif
        }
    }
}
