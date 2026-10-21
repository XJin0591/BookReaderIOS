import SwiftUI

struct ChapterReaderView: View {
    let chapter: BookChapter
    let source: BookSource

    var body: some View {
        Text(chapter.title)
            .navigationTitle(chapter.title)
    }
}
