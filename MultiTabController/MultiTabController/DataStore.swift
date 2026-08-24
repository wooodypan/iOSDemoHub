import Foundation

// 示例数据源：仅供 Demo / 集成测试使用，不属于库本体。
// 真实接入时，请替换为你的业务数据，只要符合 PPContentItem 结构即可。
public struct DataStore {
    public static let techArticles: [PPContentItem] = (1...20).map {
        PPContentItem(
            id: $0,
            title: "Tech Article \($0)",
            body: "This is the detailed content of tech article \($0). Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
            category: "Tech"
        )
    }

    public static let newsArticles: [PPContentItem] = (1...20).map {
        PPContentItem(
            id: $0 + 100,
            title: "News Article \($0)",
            body: "This is the detailed content of news article \($0). Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
            category: "News"
        )
    }
}
