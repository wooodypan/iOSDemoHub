import Foundation

struct Article {
    let id: Int
    let title: String
    let body: String
    let category: String
}

struct DataStore {
    static let techArticles: [Article] = (1...20).map {
        Article(id: $0, title: "Tech Article \($0)", body: "This is the detailed content of tech article \($0). Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.", category: "Tech")
    }

    static let newsArticles: [Article] = (1...20).map {
        Article(id: $0 + 100, title: "News Article \($0)", body: "This is the detailed content of news article \($0). Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.", category: "News")
    }
}
