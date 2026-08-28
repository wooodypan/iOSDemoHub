// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MarkdownEditorKit",
    platforms: [
        .iOS(.v16),
        .macCatalyst(.v16),
    ],
    products: [
        .library(name: "MarkdownCoreKit", targets: ["MarkdownCore"]),
        .library(name: "MarkdownEditorKit", targets: ["MarkdownEditor"]),
        .library(name: "MarkdownPreviewKit", targets: ["MarkdownPreview"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0"),
        .package(path: "/Users/pan/Project/iOSDemo/MPITextKit"),
    ],
    targets: [
        .target(
            name: "MarkdownCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .target(
            name: "MarkdownEditor",
            dependencies: ["MarkdownCore"]
        ),
        .target(
            name: "MarkdownPreview",
            dependencies: [
                "MarkdownCore",
                .product(name: "MPITextKit", package: "MPITextKit"),
            ]
        ),
        .testTarget(
            name: "MarkdownCoreTests",
            dependencies: ["MarkdownCore"]
        ),
    ]
)
