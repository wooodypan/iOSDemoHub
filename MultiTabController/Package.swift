// swift-tools-version: 5.7
// MultiTabController 的 Swift Package Manager 支持。
// 配置与 MultiTabController.podspec 保持一致：iOS 15.0+，Swift 5.7+ 工具链。
import PackageDescription

let package = Package(
    name: "MultiTabController",
    platforms: [
        // 与 podspec 的 s.platforms = { :ios => '15.0' } 一致
        .iOS(.v15)
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
        // 只打包库源码（MultiTabController/MultiTabController/ 下的 swift 文件），
        // 不含 App 宿主层（AppDelegate / Info.plist / Assets）与 NewsSplitDemo。
        .target(
            name: "MultiTabController",
            path: "MultiTabController/MultiTabController",
            // 该目录下的 README.md 是给开发者的说明文档，不属于编译单元，
            // 不排除的话 SPM 会告警 "unhandled file"。
            exclude: ["README.md"]
        )
    ]
)
