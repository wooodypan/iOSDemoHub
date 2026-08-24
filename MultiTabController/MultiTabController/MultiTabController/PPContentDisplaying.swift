import UIKit

// MARK: - PPContentHosting
// 内容页 -> 宿主 的意图上报通道（由宿主实现，DetailHostViewController 即是一个实现）。
// 有了它，内容页不需要认识 DetailHostViewController，只需要"把想做的事说出来"，
// 具体是复用预览 Tab、新建正式 Tab 还是开新窗口，全部由宿主决定。
//
// 重要：实现 PPContentDisplaying 的内容页必须用 weak 持有 contentHost。
// 因为宿主会强引用内容页（tabs 数组持有它以实现保活），内容页再强引用宿主就会形成循环引用。
public protocol PPContentHosting: AnyObject {

    /// 内容页的"编辑态"发生变化。
    /// 传 true 时，宿主会把承载它的 Tab 固定为正式 Tab（不再被后续的预览操作复用覆盖），
    /// 这对应 VS Code 里"编辑了预览 Tab 的内容，它就变成普通 Tab"的行为。
    func contentViewController(_ contentViewController: UIViewController,
                               didChangeEditedState isEdited: Bool)

    /// 内容页请求以指定方式打开一个内容项（例如详情页里的"在新 Tab / 新窗口中打开"）。
    /// 复用已有的 PPContentOpenMode，不再另造一套枚举。
    func contentViewController(_ contentViewController: UIViewController,
                               requestsOpen item: PPContentItem,
                               mode: PPContentOpenMode)
}

// MARK: - PPContentDisplaying
// 宿主 -> 内容页 的唯一要求：能被内容项配置、能接受宿主注入的上报通道。
// 库本身不含任何内容 UI，Tab 里显示什么完全由集成方决定，只要满足这个协议即可。
public protocol PPContentDisplaying: UIViewController {

    /// 宿主注入的上报通道。实现方**必须**声明为 `weak var`，否则会与宿主形成循环引用。
    /// 为 nil 表示当前没有多 Tab 宿主（例如 iPhone 上被直接 push 出来），
    /// 内容页可据此隐藏"新 Tab / 新窗口"这类只在分栏环境下有意义的入口。
    var contentHost: PPContentHosting? { get set }

    /// 用内容项配置页面。
    /// 注意：宿主可能在 view 加载之前就调用它（Tab 是先创建后显示的），
    /// 实现方应当先把数据存下来，等 viewDidLoad 之后再渲染，不要在这里直接访问控件。
    func configure(with item: PPContentItem)
}

// MARK: - PPContentViewControllerProvider
// 内容页工厂：宿主每新建一个 Tab 就调用一次，返回一个全新的内容页实例。
// 由集成方提供（必填），这是库能做到"不认识具体内容"的关键。
public typealias PPContentViewControllerProvider = () -> PPContentDisplaying
