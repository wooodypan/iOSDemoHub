import UIKit

// 设备布局类型：公开枚举，供外部判断当前环境。
public enum DeviceLayout {
    case iPhone
    case iPadOrMac
}

// 设备判断工具：公开静态属性。
public struct DeviceHelper {
    public static var currentLayout: DeviceLayout {
        #if targetEnvironment(macCatalyst)
        return .iPadOrMac
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .iPadOrMac
        }
        return .iPhone
        #endif
    }
}
