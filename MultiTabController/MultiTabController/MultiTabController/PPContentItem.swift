import Foundation

// 内容模型：对外公开，供外部使用者构造/读取。
// 这是库里“可被打开 / 展示在详情 Tab 中的内容项”的通用抽象。
// 集成方可以用自己的业务模型映射成 PPContentItem 来驱动 MultiTabController。
public struct PPContentItem {
    // 用 String 而非 Int：业务侧的主键形态各异（UUID、字符串 ID、复合 key），
    // String 能无损承载它们，Int 则会逼着集成方做一次映射。
    public let id: String
    public let title: String
    public let body: String
    public let category: String

    // 显式公开成员初始化器：
    // 注意：public 结构体的 memberwise init 默认是 internal，
    // 不显式声明 public init 的话，外部（集成方）无法构造 PPContentItem。
    public init(id: String, title: String, body: String, category: String) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
    }
}
