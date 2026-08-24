import UIKit

// MARK: - TabBarBuilder
// PPTabBarController 的便捷工厂。
// PPTabBarController 是自定义的 UIViewController 子类（不是系统 UITabBarController），
// 它不读取子控制器的 tabBarItem，而是由 [PPTabItem]（标题 + 图标）定义每一个 Tab 按钮。
//
// 相比直接调用 PPTabBarController 的初始化器，这里多了一层"数量对齐"的保护：
// 子控制器与 Tab 模型数量不一致时取较小值，而不是直接 precondition 中断。
public enum TabBarBuilder {

    /// 用"子控制器数组 + Tab 模型数组"构造标签栏控制器（可配图标）。
    /// - Parameters:
    ///   - viewControllers: 每个元素就是一个 Tab 对应的控制器（例如已包好 UINavigationController 的列表页）。
    ///   - items: 与数组按索引一一对应的 Tab 模型（标题 + 可选图标）；数量不一致时以较小数目为准。
    ///   - initialIndex: 初始选中下标，会被钳制到合法范围内。
    /// - Returns: 配置好的 PPTabBarController，可继续配置选中色、监听切换、程序化切 Tab。
    /// - Note: 两个数组都为空时无法构成标签栏，会触发 PPTabBarController 的 precondition。
    public static func build(
        viewControllers: [UIViewController],
        items: [PPTabItem],
        initialIndex: Int = 0
    ) -> PPTabBarController {
        // PPTabBarController 要求"子控制器数量 == Tab 模型数量"，这里取两者较小值对齐。
        let count = min(viewControllers.count, items.count)

        return PPTabBarController(
            viewControllers: Array(viewControllers.prefix(count)),
            items: Array(items.prefix(count)),
            initialIndex: initialIndex
        )
    }

    /// 只有标题、不需要图标时的便捷重载。
    /// - Parameters:
    ///   - viewControllers: 每个元素就是一个 Tab 对应的控制器。
    ///   - titles: 与数组按索引一一对应的 Tab 标题；数量不一致时以较小数目为准。
    ///   - initialIndex: 初始选中下标，会被钳制到合法范围内。
    public static func build(
        viewControllers: [UIViewController],
        titles: [String],
        initialIndex: Int = 0
    ) -> PPTabBarController {
        build(
            viewControllers: viewControllers,
            items: titles.map { PPTabItem(title: $0) },
            initialIndex: initialIndex
        )
    }
}
