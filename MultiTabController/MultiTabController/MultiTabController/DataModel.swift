import Foundation

// 文章模型：公开为 public，供外部使用者构造/读取。
public struct Article {
    public let id: Int
    public let title: String
    public let body: String
    public let category: String

    // 显式公开成员初始化器：
    // 注意：public 结构体的 memberwise init 默认是 internal，
    // 不显式声明 public init 的话，外部（集成方）无法构造 Article。
    public init(id: Int, title: String, body: String, category: String) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
    }
}

// 示例数据源：公开静态属性，方便外部直接拿假数据做演示。
public struct DataStore {
    public static let techArticles: [Article] = (1...20).map {
        Article(id: $0, title: "Tech Article \($0)", body: "This is the detailed content of tech article \($0). Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.", category: "Tech")
    }

    public static let newsArticles: [Article] = (1...20).map {
        Article(id: $0 + 100, title: "News Article \($0)", body: "This is the detailed content of news article \($0). Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.", category: "News")
    }
}
