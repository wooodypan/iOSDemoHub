import UIKit

// MARK: - RootBuilder
// 应用“根控制器”的工厂：按设备选择布局。
// 具体的左侧列表 / 示例数据由调用方（宿主 App）通过闭包注入，
// 本工厂只负责“按设备返回对应根控制器”，不感知任何业务内容（保持库纯净）。
public enum RootBuilder {

    /// 根据当前设备类型，返回对应的根控制器：
    ///   - iPhone：调用 iPhoneRoot 构建（通常是 PPTabBarController 包着若干列表）；
    ///   - iPad / Mac：调用 iPadOrMacRoot 构建（通常是 SplitContainerViewController）。
    /// 两个闭包均由调用方提供，库本身不包含任何示例列表或数据。
    public static func makeRoot(
        iPhoneRoot: @escaping () -> UIViewController,
        iPadOrMacRoot: @escaping () -> UIViewController
    ) -> UIViewController {
        switch DeviceHelper.currentLayout {
        case .iPhone:
            return iPhoneRoot()
        case .iPadOrMac:
            return iPadOrMacRoot()
        }
    }
}
