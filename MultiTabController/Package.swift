// swift-tools-version: 5.0
// MultiTabController 的 Swift Package Manager 支持。
// 配置与 MultiTabController.podspec 保持一致：iOS 12.0+，Swift 5.0+ 工具链。
import PackageDescription

let package = Package(
    name: "MultiTabController",
    platforms: [
        // 与 podspec 的 s.platforms = { :ios => '12.0' } 一致
        .iOS(.v12)
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
            path: "MultiTabController/MultiTabController/MultiTabController",
            // 该目录下的 README.md 是给开发者的说明文档，不属于编译单元，
            // 不排除的话 SPM 会告警 "unhandled file"。
            exclude: ["README.md"]
        )
    ]
)
