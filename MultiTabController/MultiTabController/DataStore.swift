import Foundation

// 示例数据源：仅供 Demo / 集成测试使用，不属于库本体。
// 真实接入时，请替换为你的业务数据，只要符合 PPContentItem 结构即可。
public struct DataStore {
    public static let techArticles: [PPContentItem] = (1...20).map {
        PPContentItem(
            id: "tech-\($0)",
            title: "Tech Article \($0)",
            body: "This is the detailed content of tech article \($0). Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
            category: "Tech"
        )
    }

    public static let newsArticles: [PPContentItem] = (1...20).map {
        PPContentItem(
            id: "news-\($0)",
            title: "News Article \($0)",
            body: "This is the detailed content of news article \($0). Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
            category: "News"
        )
    }

    /// 全部示例内容，供冷启动恢复时按 id 反查。
    public static let allItems: [PPContentItem] = techArticles + newsArticles

    // 按 id 建一张表。恢复会在主线程、启动阶段逐条调用解析器，所以用字典保证 O(1)，
    // 而不是每次都对 allItems 做一次线性遍历。
    // 万一有重复 id（示例数据里没有），保留先出现的那条，避免 Dictionary 初始化直接崩。
    private static let itemsByID: [String: PPContentItem] = Dictionary(
        allItems.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    /// 按 id 找内容；找不到返回 nil（例如文章被删、id 规则变了）。
    public static func item(withID id: String) -> PPContentItem? {
        itemsByID[id]
    }
}
