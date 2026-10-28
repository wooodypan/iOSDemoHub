import UIKit

// MARK: - 语义颜色：浅色 / 深色 / iOS 12 回退
// 本文件是「页面所有颜色」的唯一出处：页面代码只引用这里的 pp_xxx，不再自己写死白/黑/灰。
// 这样做的好处有两个：
//   1. 深色模式只需要在这里处理一次，页面代码一行都不用改；
//   2. iOS 12 没有系统级深色模式（深色模式是 iOS 13 才引入的），
//      所以回退值只给浅色那一份，在 iOS 12 上的表现与改动前完全一致。
// 注意：动态颜色是「解析时才求值」的 —— 把 UIColor 对象设给视图后，系统切换浅色/深色会自动重新解析并重绘，
// 不需要我们手动刷新页面（唯一例外是 CALayer 上的 CGColor，那个不跟外观走，需要单独处理）。
extension UIColor {

    // MARK: - 动态色工厂

    /// 造一个「浅色一份、深色一份」的动态颜色，系统切换外观时会自动重新解析。
    /// - Parameters:
    ///   - light: 浅色外观下使用的颜色。
    ///   - dark: 深色外观下使用的颜色。
    static func pp_adaptive(light: UIColor, dark: UIColor) -> UIColor {
        if #available(iOS 13.0, *) {
            // 系统每次解析这个颜色时都会调用这个闭包，并告诉我们「当前是什么外观」。
            return UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        }
        // iOS 12 永远拿不到深色外观，固定返回浅色那一份。
        return light
    }

    // MARK: - 背景

    /// 系统背景色回退：iOS 13+ 用 `.systemBackground`（浅色白 / 深色黑），iOS 12 用白色。
    static var pp_systemBackground: UIColor {
        if #available(iOS 13.0, *) {
            return .systemBackground
        }
        return .white
    }

    /// 选中标签页的底色（`DetailHostViewController.tabSelectedBackgroundColor` 的默认值）。
    /// 浅色下是浅浅的灰（与改动前一致）；深色下换成比背景亮一档的灰，选中的标签才浮得出来。
    static var pp_tabSelectedBackground: UIColor {
        return pp_adaptive(
            light: UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0),
            dark: UIColor(white: 0.28, alpha: 1.0)
        )
    }

    /// Tab 处于编辑态（有未保存的修改）时，替代关闭按钮 x 的那个小圆点颜色。
    /// 浅色下取中灰：压在浅灰的 Tab 底色上既不刺眼、又能一眼看见；
    /// 深色下换成半透明白，纯黑背景上才浮得出来。
    static var pp_editingIndicator: UIColor {
        return pp_adaptive(
            light: UIColor(white: 0.62, alpha: 1.0),
            dark: UIColor(white: 1.0, alpha: 0.55)
        )
    }

    /// 左侧列表选中行的底色（模仿 VS Code 资源管理器里被选中的文件）。
    /// 浅色下是中性灰；深色下换成比纯黑背景亮一档的灰。
    static var pp_selectedRowBackground: UIColor {
        return pp_adaptive(
            light: UIColor(white: 0.90, alpha: 1.0),
            dark: UIColor(white: 0.26, alpha: 1.0)
        )
    }

    // MARK: - 文字

    /// 主要文字色（标题、正文）：iOS 13+ 用 `.label`（浅色近黑 / 深色近白），iOS 12 用黑色。
    static var pp_label: UIColor {
        if #available(iOS 13.0, *) {
            return .label
        }
        return .black
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

    // MARK: - 分隔线

    /// 明显的分隔线（左右分栏之间那条竖线、底部标签栏上方那条横线）。
    /// 浅色下沿用原来的 0.85 浅灰；深色下换成半透明白 —— 深灰画在纯黑背景上根本看不见，纯浅灰又太刺眼。
    static var pp_separator: UIColor {
        return pp_adaptive(
            light: UIColor(white: 0.85, alpha: 1.0),
            dark: UIColor(white: 1.0, alpha: 0.22)
        )
    }

    /// 极淡的分隔线（多 Tab 条与内容区之间那条几乎看不见的线）。
    /// 浅色下沿用原来的 0.97；深色下用透明度更低的白，保持「若隐若现」的观感。
    static var pp_hairlineSeparator: UIColor {
        return pp_adaptive(
            light: UIColor(white: 0.97, alpha: 1.0),
            dark: UIColor(white: 1.0, alpha: 0.12)
        )
    }
}
