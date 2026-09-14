// swift-tools-version:5.0
// 注意：tools-version 5.0 要求"swift-tools-version:"后不能有空格，
// 且 platforms 只能用字符串形式（.iOS("12.0")），.v 枚举形式需要 tools 5.1+。
// MultiTabController 的 Swift Package Manager 支持。
// 配置与 MultiTabController.podspec 保持一致：iOS 12.0+，Swift 5.0+ 工具链。
import PackageDescription

let package = Package(
    name: "MultiTabController",
    platforms: [
        // 与 podspec 的 s.platforms = { :ios => '12.0' } 一致
        .iOS("12.0")
    ],
    products: [
        // 库产品名 = MultiTabController，外部工程 `import MultiTabController` 即可使用
        .library(
            name: "MultiTabController",
            targets: ["MultiTabController"]
        )
    ],
    targets: [
        // 源码目录与 podspec 的 source_files 指向同一处：
        // 只打包库源码（MultiTabController/MultiTabController/MultiTabController/ 下的 swift 文件），
        // 不含 App 宿主层（AppDelegate / ArticleListViewController / DataStore / Info.plist / Assets）与 NewsSplitDemo。
        .target(
            name: "MultiTabController",
            path: "MultiTabController/MultiTabController/MultiTabController"
        )
    ]
)
