import SwiftUI

struct SearchView: View {
    @ObservedObject var model: AppModel
    @State private var keyword = ""

    var body: some View {
        VStack {
            HStack {
                TextField("输入书名", text: $keyword)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("搜索关键词")
                Button("搜索") { Task { await model.searchCoordinator.search(keyword, sources: model.sources) } }
                    .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            Text("已启用书源：\(model.sources.filter(\.enabled).count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.searchCoordinator.books.isEmpty && model.searchCoordinator.outcomes.isEmpty {
                ContentUnavailableView("搜索书籍", systemImage: "magnifyingglass", description: Text("添加书源后，即可搜索书籍。"))
            } else {
                List {
                    Section("搜索结果") {
                        ForEach(model.searchCoordinator.books) { book in
                            resultRow(book)
                        }
                    }
                    Section("书源状态") {
                        ForEach(model.searchCoordinator.outcomes) { outcome in
                            HStack {
                                Text(outcome.sourceName)
                                Spacer()
                                Text(statusText(outcome.status)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("搜索")
    }

    private func statusText(_ status: SourceSearchOutcome.Status) -> String {
        switch status {
        case .found(let count): return "找到 \(count) 条"
        case .empty: return "无结果"
        case .failed(let message): return "失败：\(message)"
        case .timedOut: return "超时"
        }
    }

    @ViewBuilder
    private func resultRow(_ book: SearchBook) -> some View {
        if let sourceID = book.sourceIDs.first(where: { book.resolvedDetailURL(forSourceID: $0) != nil }),
           let source = model.sources.first(where: { $0.id == sourceID }),
           let detailURL = book.resolvedDetailURL(forSourceID: sourceID) {
            let detailBook = SearchBook(
                id: book.id,
                title: book.title,
                author: book.author,
                detailURL: detailURL.absoluteString,
                sourceIDs: [sourceID]
            )
            NavigationLink {
                BookDetailView(book: detailBook, source: source)
            } label: {
                bookRow(book)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                bookRow(book)
                Text("该书源未提供详情地址")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bookRow(_ book: SearchBook) -> some View {
        VStack(alignment: .leading) {
            Text(book.title)
            if let author = book.author { Text(author).font(.caption).foregroundStyle(.secondary) }
            Text("来源：\(book.sourceIDs.count) 个").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
