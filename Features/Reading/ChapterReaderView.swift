import SwiftUI

struct ChapterReaderView: View {
    let chapter: BookChapter
    let source: BookSource

    @StateObject private var model: ChapterReaderViewModel

    init(chapter: BookChapter, source: BookSource) {
        self.chapter = chapter
        self.source = source
        _model = StateObject(wrappedValue: ChapterReaderViewModel())
    }

    var body: some View {
        Group {
            if model.isLoading && model.content == nil {
                ProgressView("正在加载章节…")
            } else if let error = model.errorMessage {
                ContentUnavailableView {
                    Label("章节加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await load() } }
                }
            } else if let content = model.content {
                ScrollView {
                    Text(content.text)
                        .font(.system(size: 20))
                        .lineSpacing(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                ProgressView("正在加载章节…")
            }
        }
            .navigationTitle(chapter.title)
            .task {
                if model.content == nil && model.errorMessage == nil {
                    await load()
                }
            }
    }

    private func load() async {
        await model.load(chapter: chapter, source: source)
    }
}
