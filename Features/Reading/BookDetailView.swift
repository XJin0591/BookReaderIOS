import SwiftUI

struct BookDetailView: View {
    let book: SearchBook
    let source: BookSource

    @StateObject private var model: BookDetailViewModel

    init(book: SearchBook, source: BookSource) {
        self.book = book
        self.source = source
        _model = StateObject(wrappedValue: BookDetailViewModel())
    }

    var body: some View {
        Group {
            if model.isLoading && model.detail == nil {
                ProgressView("正在加载书籍…")
            } else if let error = model.errorMessage {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await load() } }
                }
            } else if let detail = model.detail {
                List {
                    Section {
                        if let coverURL = detail.coverURL, let url = URL(string: coverURL) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(maxHeight: 220)
                        }
                        Text(detail.title).font(.title2.bold())
                        if let author = detail.author { Text(author).foregroundStyle(.secondary) }
                        if let intro = detail.intro { Text(intro) }
                    }
                    Section("章节目录") {
                        ForEach(model.chapters) { chapter in
                            NavigationLink {
                                ChapterReaderView(chapter: chapter, source: source)
                            } label: {
                                Text(chapter.title)
                            }
                        }
                    }
                }
            } else {
                ProgressView("正在加载书籍…")
            }
        }
        .navigationTitle(model.detail?.title ?? book.title)
        .task {
            if model.detail == nil && model.errorMessage == nil {
                await load()
            }
        }
    }

    private func load() async {
        await model.load(book: book, source: source)
    }
}
