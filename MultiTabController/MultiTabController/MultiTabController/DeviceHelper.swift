import UIKit

enum DeviceLayout {
    case iPhone
    case iPadOrMac
}

struct DeviceHelper {
    static var currentLayout: DeviceLayout {
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
