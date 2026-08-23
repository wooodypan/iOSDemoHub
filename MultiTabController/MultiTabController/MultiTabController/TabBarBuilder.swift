import UIKit

// MARK: - TabBarBuilder
// 一个可复用的“PPTabBarController 工厂”。
// PPTabBarController 是自定义的 UIViewController 子类（不是系统 UITabBarController），
// 它不读取子控制器的 tabBarItem，而是通过初始化时传入的
// ButtonConfiguration（标题 + 图标）数组来定义每一个 Tab 按钮。
// 只要传入“子控制器数组 + 对应的标题”，就能构造出带正确 Tab 的标签栏控制器。
//
// 对外公开：但注意 PPTabBarController 是库内部实现类型（不对外公开），
// 所以这里的返回值声明为 UIViewController（PPTabBarController 是它的子类，向上转型返回）。
public enum TabBarBuilder {

    /// 根据传入的子控制器数组和标题，构造一个 PPTabBarController。
    /// - Parameters:
    ///   - viewControllers: 每个元素就是一个 Tab 对应的控制器（例如已包好 UINavigationController 的列表页）。
    ///   - titles: 与数组按索引一一对应的 Tab 标题；数量不一致时以较小数目为准。
    /// - Returns: 配置好的标签栏控制器（UIViewController 类型），可直接作为根控制器或嵌入其它容器。
    public static func build(viewControllers: [UIViewController], titles: [String]) -> UIViewController {
        // PPTabBarController 要求“子控制器数量 == 按钮配置数量”，这里取两者较小值对齐。
        let count = min(viewControllers.count, titles.count)

        // 用标题生成每个 Tab 的 ButtonConfiguration（图片暂留空，可按需扩展）。
        let configurations: [PPTabBarController.ButtonConfiguration] = (0..<count).map { index in
            PPTabBarController.ButtonConfiguration(title: titles[index], image: nil)
        }

        // 用“子控制器数组 + 按钮配置数组”初始化（这是 PPTabBarController 提供的指定初始化器）。
        return PPTabBarController(
            viewControllers: Array(viewControllers.prefix(count)),
            buttonConfigurations: configurations
        )
    }
}
