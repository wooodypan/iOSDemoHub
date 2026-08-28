# MarkdownEditorKit

基于 [swift-markdown](https://github.com/swiftlang/swift-markdown)（Apple 官方，cmark-gfm 的 Swift AST 封装）解析、
[MPITextKit](https://github.com/meitu/MPITextKit) 高性能渲染的 iOS markdown 编辑器组件，兼容 Mac Catalyst。

## 特性

- **原地高亮编辑**：`UITextView` 直接编辑 markdown 源码，AST 驱动实时语法高亮（语法符号保留并弱化显示）
- **渲染预览**：`MPITextRenderer` 后台排版 + `MPILabel` 异步渲染，主线程零阻塞
- **中文 / emoji 安全**：UTF-8 字节列 → UTF-16 偏移逐行换算，范围映射对多字节字符精确
- **Swift 6 strict concurrency 安全**：跨线程只传 `Sendable` 值类型（`StyleOp`），主线程统一物化属性

## 工程结构

```
Package.swift                 # 包名 MarkdownEditorKit，iOS 16 / Mac Catalyst 16
Sources/
├── MarkdownCore/             # 纯逻辑（无 UIKit）
│   ├── MDText.swift          # 归一化：\r\n|\r→\n，\t→4空格（保证解析串 == 显示串）
│   ├── UTF16LineMap.swift    # 每行 UTF-8 字节 → UTF-16 换算
│   ├── MarkdownStyler.swift  # MarkupVisitor → [StyleOp]（块级 → 行内 → 语法符号）
│   ├── MarkdownTheme.swift   # 字体/颜色主题（.light / .dark）
│   ├── MarkdownAST.swift     # MarkdownPipeline：styleOps / parse / dump
│   └── RenderedText.swift    # 预览用：剥离语法符号并重映射偏移
├── MarkdownEditor/           # UITextView 原地高亮（强制 TextKit 1）
│   ├── MarkdownEditorView.swift
│   ├── HighlightCoordinator.swift  # 120ms 防抖 + generation 丢弃过期结果
│   └── TokenAttributes.swift       # StyleToken → NSAttributedString 属性
└── MarkdownPreview/          # MPITextKit 渲染预览
    ├── PreviewRenderer.swift        # 后台构建 MPITextRenderer
    ├── PreviewAttributes.swift      # 预览专属属性（链接/代码块背景/引用条）
    ├── MPIBackgrounds.swift         # MPITextBackground 子类
    └── MarkdownPreviewView.swift    # UIScrollView + MPILabel（异步显示）
Tests/MarkdownCoreTests/      # 27 个用例，含中文/emoji 偏移断言
Demo/MarkdownDemo.xcodeproj   # Demo App（iOS + Mac Catalyst）
```

## 数据流

```
用户输入 (UITextView, TextKit 1)
  → 120ms 防抖 + generation 计数
  → 后台: Document(parsing:) → MarkdownStyler → [StyleOp]（Sendable 值类型）
  → 主线程: 校验文本未变 → 保存光标 → 批量应用属性 → 恢复光标
预览:
  → 后台: 剥离符号 → 属性物化 → MPITextRenderAttributesBuilder → MPITextRenderer
  → 主线程: label.textRenderer = renderer（displaysAsynchronously）
```

## 快速上手

```swift
import MarkdownEditor
import MarkdownPreview

// 编辑器
let editor = MarkdownEditorView()
editor.text = "# 你好，**世界**"
editor.rehighlight()

// 预览
let preview = MarkdownPreviewView()
preview.update(source: editor.text ?? "")
```

## Demo

`Demo/MarkdownDemo.xcodeproj` 单 target（`SUPPORTS_MACCATALYST=YES`），三段式导航：编辑 / 预览 / AST 转储。

```bash
# iOS 模拟器
xcodebuild -project Demo/MarkdownDemo.xcodeproj -scheme MarkdownDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build

# Mac Catalyst
xcodebuild -project Demo/MarkdownDemo.xcodeproj -scheme MarkdownDemo \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' build

# 单元测试
xcodebuild test -scheme MarkdownEditorKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:MarkdownCoreTests

# UI 测试（打字黄金路径）
xcodebuild test -project Demo/MarkdownDemo.xcodeproj -scheme MarkdownDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:MarkdownDemoUITests
```

启动参数（便于自动化验证）：`-mode edit|preview|ast`、`-theme dark`、`-perf`（控制台打印大文档基准）。

## 性能基准（iPhone 15 Pro 模拟器，Release -O）

| 文档规模 | styleOps（高亮管道） | rendered + 预览排版 |
|---|---|---|
| 10k 字符 | 4.7 ms | 65 ms |
| 100k 字符 | 106 ms | 408 ms |

高亮管道全程后台执行 + 防抖，打字主线程不阻塞；预览仅在切入预览页时构建。

## 关键实现说明

- **偏移映射**：swift-markdown 的 `SourceLocation.column` 是行首起 UTF-8 字节数（1 起），直接当字符偏移会在中文/emoji 上错位；`UTF16LineMap` 逐行换算，映射失败时 clamp 到行范围兜底
- **编辑器禁用 `.link` 属性键**：`UITextView` 会拦截触摸，只染颜色 + 下划线；预览端才用 `MPITextLinkAttributeName`
- **IME 保护**：`markedTextRange != nil`（中文组字中）跳过高亮重排
- **MPITextKit 默认值陷阱**：`MPITextRenderAttributesBuilder` 默认单行尾截断，预览必须显式 `.byWordWrapping` + `maximumNumberOfLines = 0`
- **依赖**：`MPITextKit` 采用本地路径依赖 `/Users/pan/Project/iOSDemo/MPITextKit`（可就地补丁）
