import SwiftUI

struct BookDetailView: View {
    let book: SearchBook
    let source: BookSource

    var body: some View {
        Text(book.title)
            .navigationTitle(book.title)
    }
}
