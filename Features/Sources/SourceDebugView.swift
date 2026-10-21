import SwiftUI

struct SourceDebugView: View {
    let source: BookSource
    @State private var keyword = "三国演义"
    @State private var message = ""
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("测试关键词") {
                TextField("关键词", text: $keyword)
                Button(isTesting ? "测试中…" : "测试书源") { test() }.disabled(isTesting)
            }
            if !message.isEmpty { Text(message) }
        }
        .navigationTitle(source.bookSourceName)
    }

    private func test() {
        isTesting = true
        Task {
            defer { isTesting = false }
            do {
                let books = try await LegadoSourceSearchService().search(source: source, keyword: keyword)
                message = books.isEmpty ? "请求成功，但没有找到结果。" : "找到 \(books.count) 条结果。"
            } catch { message = "测试失败：\(error.localizedDescription)" }
        }
    }
}
