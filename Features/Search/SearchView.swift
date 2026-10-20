import SwiftUI

struct SearchView: View {
    var body: some View {
        ContentUnavailableView("搜索书籍", systemImage: "magnifyingglass", description: Text("添加书源后，即可搜索书籍。"))
            .navigationTitle("搜索")
    }
}
