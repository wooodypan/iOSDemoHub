import UIKit

// Tab 按钮模型：对外公开，供外部构造 PPTabBarController 的每一个 Tab。
// PPTabBarController 不读取子控制器的 tabBarItem，而是由这个模型定义标题与图标，
// 所以标题、普通态图标、选中态图标都在这里给。
public struct PPTabItem {

    /// Tab 标题（同时会被 PPTabBarController 同步到 navigationItem 的 title 上）。
    public let title: String

    /// 普通态图标。传 nil 表示只显示文字。
    public let image: UIImage?

    /// 选中态图标。传 nil 时选中态复用 image，仅通过 tintColor 区分选中状态。
    public let selectedImage: UIImage?

    /// 显式公开成员初始化器：
    /// public 结构体的 memberwise init 默认是 internal，不显式声明外部无法构造。
    public init(title: String, image: UIImage? = nil, selectedImage: UIImage? = nil) {
        self.title = title
        self.image = image
        self.selectedImage = selectedImage
    }
}
