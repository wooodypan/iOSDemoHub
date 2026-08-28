import Foundation

/// Built-in document used to exercise every supported syntax element.
enum SampleDocument {

    static let text: String = """
    # Markdown 编辑器

    基于 **swift-markdown** 解析抽象语法树，由 **MPITextKit** 提供高性能异步渲染。

    ## 特性

    - 原地语法高亮，输入即渲染
    - 后台解析，主线程零阻塞
    - 支持 *斜体*、**粗体**、~~删除线~~ 与 `行内代码`
    - 兼容 iOS 与 Mac Catalyst

    ## 代码示例

    ```swift
    let document = MarkdownPipeline.parse(source)
    let renderer = PreviewRenderer.render(
        source: source,
        width: columnWidth,
        theme: .light
    )
    ```

    ## 链接与引用

    访问 [Apple 开发者文档](https://developer.apple.com) 了解更多。

    > 好的工具让人专注于内容本身。
    > —— 一位快乐的写作者

    ## 表格

    | 模块 | 职责 | 语言 |
    | --- | --- | --- |
    | MarkdownCore | AST 解析与令牌映射 | Swift |
    | MarkdownEditor | 原地高亮编辑 | Swift |
    | MarkdownPreview | 异步渲染预览 | Swift + ObjC |

    ---

    ### 长文本性能

    这段文字用来验证长文档下的打字流畅度。编辑器会在停止输入约 120 毫秒后触发一次后台解析，解析结果以样式操作（StyleOp）的形式回到主线程批量应用，全程不触碰字符内容，因此光标与撤销栈保持稳定。中文、emoji 😀 与 English mixed 内容的偏移映射都经过 UTF-8 到 UTF-16 的精确换算，确保高亮范围不会错位。

    1. 有序列表第一项
    2. 有序列表第二项
    3. 包含 **粗体** 与 [链接](https://swift.org) 的项目

    祝写作愉快！
    """
}
