import UIKit

// MARK: - iOS 12 语义颜色回退
// 以下扩展为 iOS 12 提供系统语义颜色的近似回退值；
// iOS 13+ 直接返回系统原生颜色，行为完全一致。
extension UIColor {

    /// 系统背景色回退：iOS 13+ 用 `.systemBackground`，iOS 12 用白色。
    static var pp_systemBackground: UIColor {
        if #available(iOS 13.0, *) {
            return .systemBackground
        }
        return .white
    }

    /// 次要标签颜色回退：iOS 13+ 用 `.secondaryLabel`，iOS 12 用 60% 黑色。
    static var pp_secondaryLabel: UIColor {
        if #available(iOS 13.0, *) {
            return .secondaryLabel
        }
        return UIColor(white: 0.4, alpha: 1.0)
    }

    /// 三级标签颜色回退：iOS 13+ 用 `.tertiaryLabel`，iOS 12 用 30% 黑色。
    static var pp_tertiaryLabel: UIColor {
        if #available(iOS 13.0, *) {
            return .tertiaryLabel
        }
        return UIColor(white: 0.7, alpha: 1.0)
    }
}
